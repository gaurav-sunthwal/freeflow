import AppKit

/// Keeps FreeFlow up to date from GitHub Releases.
///
/// FreeFlow is built from source on each Mac, so an update = download the release's source, build it in the
/// background with the same install script, wait until the user isn't dictating, then swap the app and relaunch.
@MainActor
final class Updater: ObservableObject {
    static let shared = Updater()

    enum Status: Equatable {
        case idle, checking, upToDate
        case building(String)
        case ready(String)
        case failed(String)
    }

    @Published private(set) var status: Status = .idle
    @Published private(set) var latestVersion: String?

    static let repo = "gaurav-sunthwal/freeflow"
    let currentVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"

    private var timer: Timer?
    private let checkInterval: TimeInterval = 6 * 60 * 60
    private let justUpdatedKey = "justUpdatedTo"
    private let skippedTagKey = "skippedUpdateTag"

    private var supportDir: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("FreeFlow", isDirectory: true)
    }

    func startAutomaticChecks() {
        if let v = UserDefaults.standard.string(forKey: justUpdatedKey) {
            UserDefaults.standard.removeObject(forKey: justUpdatedKey)
            if v == currentVersion { Coordinator.shared.overlay.set(.message("FreeFlow updated to \(v) ✓")) }
        }
        // First check shortly after launch, then every few hours.
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [weak self] in
            Task { await self?.check(userInitiated: false) }
        }
        timer = Timer.scheduledTimer(withTimeInterval: checkInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.check(userInitiated: false) }
        }
    }

    // MARK: Checking

    func check(userInitiated: Bool) async {
        switch status {
        case .building, .ready, .checking: return
        default: break
        }
        guard userInitiated || Settings.shared.autoUpdate else { return }
        status = .checking
        do {
            let tag = try await latestReleaseTag()
            let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
            latestVersion = version
            if Self.isNewer(version, than: currentVersion), tag != UserDefaults.standard.string(forKey: skippedTagKey) {
                await install(tag: tag, version: version)
            } else {
                status = .upToDate
            }
        } catch {
            status = userInitiated ? .failed(error.localizedDescription) : .idle
        }
    }

    private func latestReleaseTag() async throws -> String {
        var req = URLRequest(url: URL(string: "https://api.github.com/repos/\(Self.repo)/releases/latest")!)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("FreeFlow/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 20
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw UpdateError("No response from GitHub") }
        if http.statusCode == 404 { throw UpdateError("No releases published yet") }
        guard http.statusCode == 200,
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = json["tag_name"] as? String else { throw UpdateError("Couldn't read the latest release") }
        return tag
    }

    /// Numeric comparison of dotted versions ("1.10.0" > "1.9.2").
    nonisolated static func isNewer(_ a: String, than b: String) -> Bool {
        let pa = a.split(separator: ".").map { Int($0) ?? 0 }, pb = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0, y = i < pb.count ? pb[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    // MARK: Building

    private func install(tag: String, version: String) async {
        guard FileManager.default.fileExists(atPath: "/usr/bin/xcrun") else {
            status = .failed("Apple's developer tools are needed to update. Run: xcode-select --install")
            return
        }
        status = .building(version)
        let stage = FileManager.default.temporaryDirectory.appendingPathComponent("FreeFlow-update-\(version)")
        try? FileManager.default.removeItem(at: stage)
        try? FileManager.default.createDirectory(at: supportDir, withIntermediateDirectories: true)
        let log = supportDir.appendingPathComponent("update.log")

        let script = "curl -fsSL \"https://raw.githubusercontent.com/\(Self.repo)/\(tag)/install.sh\" | bash"
        let env = ["FREEFLOW_REF": tag, "FREEFLOW_STAGE_DIR": stage.path]
        let ok = await Self.run(script, env: env, log: log)

        let newApp = stage.appendingPathComponent("FreeFlow.app")
        guard ok, FileManager.default.fileExists(atPath: newApp.path) else {
            status = .failed("Update to \(version) failed — see ~/Library/Application Support/FreeFlow/update.log")
            return
        }
        // Guard against a release whose app version wasn't bumped — installing it would loop forever.
        let built = NSDictionary(contentsOf: newApp.appendingPathComponent("Contents/Info.plist"))?["CFBundleShortVersionString"] as? String ?? "0"
        guard Self.isNewer(built, than: currentVersion) else {
            UserDefaults.standard.set(tag, forKey: skippedTagKey)
            try? FileManager.default.removeItem(at: stage)
            status = .failed("Release \(tag) contains version \(built); skipping")
            return
        }
        status = .ready(version)
        await waitUntilIdle()
        relaunch(into: newApp, stage: stage, version: version)
    }

    /// Never interrupt a dictation: wait until FreeFlow is idle.
    private func waitUntilIdle() async {
        while Coordinator.shared.state != .idle {
            try? await Task.sleep(for: .seconds(2))
        }
    }

    /// Swaps the installed app for the new build from a detached shell, then quits so it can be replaced.
    func relaunch(into newApp: URL, stage: URL, version: String) {
        UserDefaults.standard.set(version, forKey: justUpdatedKey)
        let dest = Bundle.main.bundleURL.path
        let swap = """
        sleep 1
        while pgrep -x FreeFlow >/dev/null; do sleep 0.5; done
        rm -rf "$DEST" && ditto "$NEW" "$DEST" && xattr -dr com.apple.quarantine "$DEST" 2>/dev/null
        open "$DEST"
        rm -rf "$STAGE"
        """
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/bash")
        p.arguments = ["-c", "nohup /bin/bash -c '\(swap)' >/dev/null 2>&1 &"]
        p.environment = ProcessInfo.processInfo.environment.merging(
            ["DEST": dest, "NEW": newApp.path, "STAGE": stage.path]) { $1 }
        try? p.run()
        p.waitUntilExit()
        NSApp.terminate(nil)
    }

    private nonisolated static func run(_ command: String, env: [String: String], log: URL) async -> Bool {
        await withCheckedContinuation { cont in
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/bin/bash")
            p.arguments = ["-c", command]
            var environment = ProcessInfo.processInfo.environment
            environment["PATH"] = "/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/usr/local/bin"
            for (k, v) in env { environment[k] = v }
            p.environment = environment
            FileManager.default.createFile(atPath: log.path, contents: nil)
            if let handle = try? FileHandle(forWritingTo: log) {
                p.standardOutput = handle
                p.standardError = handle
            }
            p.terminationHandler = { cont.resume(returning: $0.terminationStatus == 0) }
            do { try p.run() } catch { cont.resume(returning: false) }
        }
    }
}

struct UpdateError: LocalizedError {
    let message: String
    init(_ m: String) { message = m }
    var errorDescription: String? { message }
}
