import Foundation
import Security

/// Optional account that backs up aggregate stats (never dictated text or audio) to the FreeFlow website API.
/// Sync is deliberately low priority: it waits a few minutes after dictating, only runs while FreeFlow is idle,
/// and uses background network priority so it never competes with dictation.
@MainActor
final class AccountService: ObservableObject {
    static let shared = AccountService()

    struct Profile: Codable, Equatable { var name: String; var email: String }

    @Published private(set) var profile: Profile?
    @Published private(set) var lastSync: Date?
    @Published private(set) var syncing = false
    @Published var lastError: String?

    /// The website that hosts the API. Override with: defaults write app.freeflow.FreeFlow accountServer <url>
    static let defaultServer = "https://freeflow-voice.vercel.app"
    var server: String { UserDefaults.standard.string(forKey: "accountServer") ?? Self.defaultServer }

    private let syncDelay: TimeInterval = 180
    private var pendingSync: DispatchWorkItem?

    private init() {
        if let data = UserDefaults.standard.data(forKey: "accountProfile") {
            profile = try? JSONDecoder().decode(Profile.self, from: data)
        }
        lastSync = UserDefaults.standard.object(forKey: "accountLastSync") as? Date
        if profile != nil && Keychain.token == nil { signOut() }
    }

    var isSignedIn: Bool { profile != nil }

    // MARK: Auth

    func signUp(name: String, email: String, password: String) async {
        await authenticate(path: "/api/auth/signup", body: ["name": name, "email": email, "password": password])
    }

    func signIn(email: String, password: String) async {
        await authenticate(path: "/api/auth/login", body: ["email": email, "password": password])
    }

    private func authenticate(path: String, body: [String: String]) async {
        lastError = nil
        do {
            let json = try await request(path, method: "POST", body: try JSONSerialization.data(withJSONObject: body), auth: false)
            guard let token = json?["token"] as? String, let user = json?["user"] as? [String: Any] else {
                throw AccountError("Unexpected server response")
            }
            Keychain.token = token
            setProfile(Profile(name: user["name"] as? String ?? "", email: user["email"] as? String ?? ""))
            await restore()
            await syncNow()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func signOut() {
        Keychain.token = nil
        profile = nil
        lastSync = nil
        UserDefaults.standard.removeObject(forKey: "accountProfile")
        UserDefaults.standard.removeObject(forKey: "accountLastSync")
    }

    func deleteAccount() async {
        do {
            _ = try await request("/api/me", method: "DELETE", body: nil, auth: true)
            signOut()
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func setProfile(_ p: Profile) {
        profile = p
        UserDefaults.standard.set(try? JSONEncoder().encode(p), forKey: "accountProfile")
    }

    // MARK: Sync

    /// Called after each dictation. Coalesces bursts into one upload a few minutes later.
    func scheduleSync() {
        guard isSignedIn else { return }
        pendingSync?.cancel()
        let work = DispatchWorkItem { [weak self] in Task { await self?.syncWhenIdle() } }
        pendingSync = work
        DispatchQueue.main.asyncAfter(deadline: .now() + syncDelay, execute: work)
    }

    private func syncWhenIdle() async {
        // Never upload during a dictation; check again shortly.
        while Coordinator.shared.state != .idle {
            try? await Task.sleep(for: .seconds(10))
        }
        await syncNow()
    }

    func syncNow() async {
        guard isSignedIn, !syncing else { return }
        syncing = true
        defer { syncing = false }
        let snapshot = HistoryStore.shared.backupSnapshot()
        do {
            let body = try await Task.detached(priority: .background) {
                try JSONSerialization.data(withJSONObject: snapshot)
            }.value
            _ = try await request("/api/stats", method: "PUT", body: body, auth: true)
            lastSync = Date()
            UserDefaults.standard.set(lastSync, forKey: "accountLastSync")
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Pulls the backed-up stats and merges them in (e.g. after reinstalling).
    private func restore() async {
        guard let json = try? await request("/api/me", method: "GET", body: nil, auth: true),
              let stats = json["stats"] as? [String: Any] else { return }
        HistoryStore.shared.mergeBackup(stats)
    }

    // MARK: HTTP

    private func request(_ path: String, method: String, body: Data?, auth: Bool) async throws -> [String: Any]? {
        guard let url = URL(string: server + path) else { throw AccountError("Invalid server address") }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.timeoutInterval = 20
        req.networkServiceType = .background
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if auth {
            guard let token = Keychain.token else { throw AccountError("Please sign in") }
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        req.httpBody = body
        let (data, resp) = try await URLSession.shared.data(for: req)
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        let json = data.isEmpty ? nil : (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        if status == 401 && auth { signOut() }
        guard (200..<300).contains(status) else {
            throw AccountError(json?["error"] as? String ?? "Server error (\(status))")
        }
        return json
    }
}

struct AccountError: LocalizedError {
    let message: String
    init(_ m: String) { message = m }
    var errorDescription: String? { message }
}

/// The sign-in token lives in the macOS Keychain, not in plain preferences.
enum Keychain {
    private static let service = "app.freeflow.account"

    static var token: String? {
        get {
            let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                        kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
            var out: AnyObject?
            guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return nil }
            return String(data: data, encoding: .utf8)
        }
        set {
            let base: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service]
            SecItemDelete(base as CFDictionary)
            guard let newValue, let data = newValue.data(using: .utf8) else { return }
            var add = base
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            SecItemAdd(add as CFDictionary, nil)
        }
    }
}
