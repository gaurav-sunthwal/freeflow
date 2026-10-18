import Foundation

/// Opt-in troubleshooting: keeps the last few dictations' audio and timings on this Mac only.
/// Enable with: defaults write app.freeflow.FreeFlow keepDebugRecordings -bool true
enum Diagnostics {
    static var enabled: Bool { UserDefaults.standard.bool(forKey: "keepDebugRecordings") }
    private static let keep = 10

    static var folder: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("FreeFlow/debug", isDirectory: true)
    }

    static func record(samples: [Float], info: [String: Any]) {
        guard enabled else { return }
        DispatchQueue.global(qos: .utility).async {
            let fm = FileManager.default
            try? fm.createDirectory(at: folder, withIntermediateDirectories: true)
            let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
            try? WAV.encode(samples).write(to: folder.appendingPathComponent("\(stamp).wav"))
            var entry = info
            entry["file"] = "\(stamp).wav"
            if let data = try? JSONSerialization.data(withJSONObject: entry), let line = String(data: data, encoding: .utf8) {
                let log = folder.appendingPathComponent("log.jsonl")
                if let h = try? FileHandle(forWritingTo: log) {
                    h.seekToEndOfFile(); h.write((line + "\n").data(using: .utf8)!); try? h.close()
                } else {
                    try? (line + "\n").write(to: log, atomically: true, encoding: .utf8)
                }
            }
            let wavs = ((try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [])
                .filter { $0.pathExtension == "wav" }.sorted { $0.lastPathComponent > $1.lastPathComponent }
            wavs.dropFirst(keep).forEach { try? fm.removeItem(at: $0) }
            // Never keep troubleshooting audio longer than 15 days.
            let cutoff = Date().addingTimeInterval(-15 * 86_400)
            for f in wavs {
                if let date = (try? f.resourceValues(forKeys: [.creationDateKey]))?.creationDate, date < cutoff {
                    try? fm.removeItem(at: f)
                }
            }
        }
    }
}
