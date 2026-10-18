import SwiftUI

/// Optional account: back up stats so they survive deleting the app.
struct AccountView: View {
    @ObservedObject var account = AccountService.shared
    @State private var creating = true
    @State private var name = ""
    @State private var email = ""
    @State private var password = ""
    @State private var busy = false
    @State private var confirmDelete = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                PageHeader(title: "Account", subtitle: "Optional. Back up your stats so they're safe if you reinstall FreeFlow.")
                if let p = account.profile { signedIn(p) } else { form }
                whatWeStore
            }
            .padding(20)
            .frame(maxWidth: 560, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var form: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                Picker("", selection: $creating) {
                    Text("Create account").tag(true)
                    Text("Sign in").tag(false)
                }
                .pickerStyle(.segmented).labelsHidden()
                if creating { TextField("Name", text: $name).textContentType(.name) }
                TextField("Email", text: $email).textContentType(.emailAddress)
                SecureField("Password (8+ characters)", text: $password).textContentType(creating ? .newPassword : .password)
                if let e = account.lastError { Text(e).font(.callout).foregroundStyle(.red) }
                HStack {
                    Spacer()
                    if busy { ProgressView().controlSize(.small) }
                    Button(creating ? "Create account" : "Sign in") {
                        busy = true
                        Task {
                            if creating { await account.signUp(name: name, email: email, password: password) }
                            else { await account.signIn(email: email, password: password) }
                            busy = false
                            if account.isSignedIn { password = "" }
                        }
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(busy || email.isEmpty || password.count < 8 || (creating && name.isEmpty))
                }
            }
            .textFieldStyle(.roundedBorder)
        }
    }

    private func signedIn(_ p: AccountService.Profile) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    Text(String(p.name.prefix(1)).uppercased())
                        .font(.title2.weight(.semibold)).foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(Theme.accent))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(p.name).font(.headline)
                        Text(p.email).font(.callout).foregroundStyle(.secondary)
                    }
                    Spacer()
                    syncStatus
                }
                if let e = account.lastError { Text(e).font(.callout).foregroundStyle(.red) }
                HStack {
                    Button("Back up now") { Task { await account.syncNow() } }.disabled(account.syncing)
                    Spacer()
                    Button("Sign out") { account.signOut() }
                    Button("Delete account", role: .destructive) { confirmDelete = true }
                }
            }
        }
        .confirmationDialog("Delete your FreeFlow account and its backup?", isPresented: $confirmDelete) {
            Button("Delete account", role: .destructive) { Task { await account.deleteAccount() } }
        } message: {
            Text("Your stats on this Mac are kept.")
        }
    }

    private var syncStatus: some View {
        Group {
            if account.syncing {
                Label("Backing up…", systemImage: "arrow.triangle.2.circlepath")
            } else if let d = account.lastSync {
                Label("Backed up \(d.formatted(.relative(presentation: .named)))", systemImage: "checkmark.icloud")
                    .foregroundStyle(Theme.green)
            } else {
                Label("Not backed up yet", systemImage: "icloud.slash")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private var whatWeStore: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                SectionLabel(text: "What's backed up")
                Label("Your stats: words, speed, streak and activity", systemImage: "chart.bar")
                Label("Filler-word counts, daily goal, Dictionary and Snippets", systemImage: "character.book.closed")
                Label("Never your dictated text or audio", systemImage: "lock.fill").foregroundStyle(Theme.green)
                Text("Backups happen quietly in the background and never slow down dictation.")
                    .font(.caption).foregroundStyle(.secondary).padding(.top, 2)
            }
            .font(.callout)
        }
    }
}

/// Compact account chip for the top-right of Home.
struct AccountChip: View {
    @ObservedObject var account = AccountService.shared
    var open: () -> Void

    var body: some View {
        Button(action: open) {
            HStack(spacing: 6) {
                if let p = account.profile {
                    Text(String(p.name.prefix(1)).uppercased())
                        .font(.caption.weight(.bold)).foregroundStyle(.white)
                        .frame(width: 18, height: 18).background(Circle().fill(Theme.accent))
                    Image(systemName: account.lastSync == nil ? "icloud" : "checkmark.icloud")
                        .foregroundStyle(account.lastSync == nil ? Color.secondary : Theme.green)
                } else {
                    Image(systemName: "person.crop.circle.badge.plus")
                    Text("Back up stats")
                }
            }
            .font(.caption)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(Capsule().fill(Color.primary.opacity(0.05)))
        }
        .buttonStyle(.plain)
        .help(account.isSignedIn ? "Account & backup" : "Create a free account to back up your stats")
    }
}
