import CoreAudio
import Foundation

struct AudioInputDevice: Identifiable, Hashable {
    let id: AudioObjectID
    let uid: String
    let name: String
    let isBluetooth: Bool
    let isBuiltIn: Bool
}

/// Thin CoreAudio helpers: device lists, Bluetooth detection, and output muting.
enum AudioDevices {
    private static let system = AudioObjectID(kAudioObjectSystemObject)

    private static func address(_ sel: AudioObjectPropertySelector, _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: sel, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    private static func read<T>(_ obj: AudioObjectID, _ sel: AudioObjectPropertySelector,
                               _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal, _ initial: T) -> T? {
        var addr = address(sel, scope)
        var value = initial
        var size = UInt32(MemoryLayout<T>.size)
        return AudioObjectGetPropertyData(obj, &addr, 0, nil, &size, &value) == noErr ? value : nil
    }

    private static func string(_ obj: AudioObjectID, _ sel: AudioObjectPropertySelector) -> String {
        var addr = address(sel)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(obj, &addr, 0, nil, &size, &value) == noErr, let v = value else { return "" }
        return v.takeRetainedValue() as String
    }

    private static func transport(_ dev: AudioObjectID) -> UInt32 {
        read(dev, kAudioDevicePropertyTransportType, kAudioObjectPropertyScopeGlobal, UInt32(0)) ?? 0
    }

    static func isBluetooth(_ dev: AudioObjectID) -> Bool {
        let t = transport(dev)
        return t == kAudioDeviceTransportTypeBluetooth || t == kAudioDeviceTransportTypeBluetoothLE
    }

    static var defaultInput: AudioObjectID? { read(system, kAudioHardwarePropertyDefaultInputDevice, kAudioObjectPropertyScopeGlobal, AudioObjectID(0)) }
    static var defaultOutput: AudioObjectID? { read(system, kAudioHardwarePropertyDefaultOutputDevice, kAudioObjectPropertyScopeGlobal, AudioObjectID(0)) }

    static func inputDevices() -> [AudioInputDevice] {
        var addr = address(kAudioHardwarePropertyDevices)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &addr, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &addr, 0, nil, &size, &ids) == noErr else { return [] }
        return ids.compactMap { id in
            var streamsAddr = address(kAudioDevicePropertyStreams, kAudioDevicePropertyScopeInput)
            var streamSize: UInt32 = 0
            guard AudioObjectGetPropertyDataSize(id, &streamsAddr, 0, nil, &streamSize) == noErr, streamSize > 0 else { return nil }
            let t = transport(id)
            guard t != kAudioDeviceTransportTypeAggregate, t != kAudioDeviceTransportTypeVirtual else { return nil }
            return AudioInputDevice(id: id, uid: string(id, kAudioDevicePropertyDeviceUID), name: string(id, kAudioObjectPropertyName),
                                    isBluetooth: t == kAudioDeviceTransportTypeBluetooth || t == kAudioDeviceTransportTypeBluetoothLE,
                                    isBuiltIn: t == kAudioDeviceTransportTypeBuiltIn)
        }
    }

    /// The microphone FreeFlow should record from for the given preference (nil = system default).
    /// "auto" uses the current system mic: a headset mic sits next to the mouth and hears far less of the room
    /// than the Mac's built-in mic, which matters much more for accuracy than headphone playback quality
    /// (other audio is muted while dictating anyway).
    static func inputDeviceUID(for preference: String) -> String? {
        switch preference {
        case "", "auto", "system":
            return nil
        default:
            return inputDevices().first { $0.uid == preference }?.uid
        }
    }

    // MARK: Output muting

    private static func outputMute(_ dev: AudioObjectID) -> Bool? {
        read(dev, kAudioDevicePropertyMute, kAudioDevicePropertyScopeOutput, UInt32(0)).map { $0 != 0 }
    }

    @discardableResult
    private static func setOutputMute(_ dev: AudioObjectID, _ muted: Bool) -> Bool {
        var addr = address(kAudioDevicePropertyMute, kAudioDevicePropertyScopeOutput)
        var settable: DarwinBoolean = false
        guard AudioObjectIsPropertySettable(dev, &addr, &settable) == noErr, settable.boolValue else { return false }
        var v: UInt32 = muted ? 1 : 0
        return AudioObjectSetPropertyData(dev, &addr, 0, nil, UInt32(MemoryLayout<UInt32>.size), &v) == noErr
    }

    private static let mutedKey = "mutedOutputDeviceUID"

    /// Mutes the default output while dictating. Only mutes (and later unmutes) a device that wasn't already muted.
    static func muteOutput() {
        guard let dev = defaultOutput, outputMute(dev) == false, setOutputMute(dev, true) else { return }
        UserDefaults.standard.set(string(dev, kAudioDevicePropertyDeviceUID), forKey: mutedKey)
    }

    /// Restores audio muted by `muteOutput()`. Also called at launch in case FreeFlow quit while muted.
    static func restoreOutput() {
        guard let uid = UserDefaults.standard.string(forKey: mutedKey) else { return }
        UserDefaults.standard.removeObject(forKey: mutedKey)
        var addr = address(kAudioHardwarePropertyDevices)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &addr, 0, nil, &size) == noErr else { return }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &addr, 0, nil, &size, &ids) == noErr else { return }
        if let dev = ids.first(where: { string($0, kAudioDevicePropertyDeviceUID) == uid }) {
            setOutputMute(dev, false)
        }
    }
}
