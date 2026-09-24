import SwiftUI

/// Round avatar with the first letter of the name, like the approved Profile design.
struct AccountAvatar: View {
    var name: String
    var size: CGFloat
    var body: some View {
        Text(String(name.trimmingCharacters(in: .whitespaces).prefix(1)).uppercased().isEmpty ? "?" : String(name.trimmingCharacters(in: .whitespaces).prefix(1)).uppercased())
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(LinearGradient(colors: [Color(red: 0.29, green: 0.64, blue: 1), Color(red: 0.04, green: 0.36, blue: 0.9)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing), in: .circle)
    }
}

/// Opens from the top row on Profile: who is signed in, backup, and Sign Out.
struct AccountView: View {
    @ObservedObject private var auth = AuthService.shared
    @AppStorage("backup.enabled") private var backupOn = true
    @AppStorage("backup.last") private var lastBackup: Double = 0
    @State private var confirmSignOut = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    private var emailText: String {
        if auth.email.isEmpty { return "Not shared" }
        return auth.email.hasSuffix("privaterelay.appleid.com") ? "Hidden by Apple" : auth.email
    }
    private var lastText: String {
        guard backupOn else { return "Off" }
        guard lastBackup > 0 else { return "Not yet" }
        let d = Date(timeIntervalSince1970: lastBackup)
        let time = d.formatted(date: .omitted, time: .shortened)
        return Calendar.current.isDateInToday(d) ? "Today, \(time)" : d.formatted(date: .abbreviated, time: .shortened)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                VStack(spacing: 4) {
                    AccountAvatar(name: auth.name, size: 84)
                    Text(auth.name.isEmpty ? "Your Account" : auth.name).font(.title2.weight(.semibold)).padding(.top, 6)
                    Label("Signed in with \(auth.provider.capitalized)", systemImage: auth.provider == "apple" ? "apple.logo" : "person.crop.circle")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity).padding(.bottom, 12)

                Card(padding: 0) {
                    VStack(spacing: 0) {
                        row("Name", auth.name.isEmpty ? "Not shared" : auth.name)
                        Divider().padding(.leading, 16)
                        row("Email", emailText)
                    }
                }
                if emailText == "Hidden by Apple" {
                    footnote("Apple keeps your real email private. Dayline gets a relay address that forwards to you.")
                }

                SectionHeader("Backup")
                Card(padding: 0) {
                    VStack(spacing: 0) {
                        Toggle("Back Up Timeline", isOn: $backupOn)
                            .padding(.horizontal, 16).frame(minHeight: 52)
                            .accessibilityIdentifier("backupToggle")
                        Divider().padding(.leading, 16)
                        row("Last Backup", lastText)
                    }
                }
                footnote("Your timeline, journal and photos list are backed up so you can restore them on a new iPhone.")

                Card(padding: 0) {
                    Button { if let url = URL(string: "https://account.apple.com") { openURL(url) } } label: {
                        HStack {
                            Text("Manage in Apple Account Settings").foregroundStyle(Theme.accent)
                            Spacer()
                            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, 16).frame(minHeight: 52).contentShape(.rect)
                    }
                }
                .padding(.top, 12)

                Button { confirmSignOut = true } label: {
                    Text("Sign Out").foregroundStyle(.red).frame(maxWidth: .infinity).frame(minHeight: 52)
                        .background(Color(.secondarySystemGroupedBackground).opacity(0.9), in: .rect(cornerRadius: 26, style: .continuous))
                        .contentShape(.rect)
                }
                .padding(.top, 12)
                .accessibilityIdentifier("accountSignOut")
            }
            .padding(.horizontal, 18).padding(.bottom, 30)
        }
        .buttonStyle(.plain)
        .background(AppBackgroundView())
        .navigationTitle("Account")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .alert("Sign Out?", isPresented: $confirmSignOut) {
            Button("Cancel", role: .cancel) {}
            Button("Sign Out", role: .destructive) { auth.signOut(); dismiss() }
        } message: {
            Text("Your timeline stays on this iPhone. Sign in again to turn backup back on.")
        }
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16).frame(minHeight: 52)
    }

    private func footnote(_ text: String) -> some View {
        Text(text).font(.footnote).foregroundStyle(.secondary).padding(.horizontal, 16).padding(.top, 2)
    }
}
