#if !APPSTORE
import AppKit
import SwiftUI

/// Settings → Chat: the Claude Code provider (the user's own `claude` CLI and
/// Claude login), the folder it runs in and its model.
struct ClaudeCodeSettingsBox: View {
    @ObservedObject var state: AppState
    @ObservedObject private var claude = ClaudeCodeChat.shared

    var body: some View {
        GroupBox("Claude Code — your Claude login") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Circle().fill(statusColor).frame(width: 8, height: 8)
                    Text(statusText).font(.system(size: 12))
                    Spacer()
                    Button("Check again") { Task { await claude.refresh() } }
                        .disabled(claude.checkingAuth)
                }

                if claude.isAvailable {
                    if state.chatProvider == .claudeCode {
                        Label("Used by the chat", systemImage: "checkmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.green)
                    } else {
                        Button("Use for the chat") { state.chatProvider = .claudeCode }
                            .buttonStyle(.borderedProminent)
                    }

                    Divider().padding(.vertical, 2)

                    HStack(spacing: 8) {
                        Text("Brain folder").font(.system(size: 12))
                        Text(folderLabel)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .truncationMode(.head)
                        Spacer()
                        Button("Choose…", action: chooseFolder)
                        if !state.brainVaultPath.isEmpty {
                            Button("Reset") { state.brainVaultPath = "" }
                        }
                    }

                    Picker("Model", selection: $state.claudeCodeModel) {
                        ForEach(ClaudeCodeChat.models, id: \.id) { model in
                            Text(model.label).tag(model.id)
                        }
                    }
                }

                Text("Runs your own `claude` command in the brain folder, so its CLAUDE.md, skills and agents apply. No API key: Claude Code uses the account you signed in with. Reading is free; writing files or running commands asks you in the notch. Add the Brain pill (Active pills) to see the brain's queues in the notch.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(6)
        }
        .task { if claude.auth == nil { await claude.refresh() } }
    }

    private var statusText: String {
        guard claude.isAvailable else {
            return String(localized: "Claude Code not found — install it, then run `claude` once to sign in.")
        }
        if claude.checkingAuth { return String(localized: "Checking your Claude login…") }
        guard let auth = claude.auth else { return String(localized: "Couldn't read the login status (`claude auth status`).") }
        guard auth.loggedIn else { return String(localized: "Not signed in — run `claude` in a terminal and log in.") }
        let plan = auth.subscriptionType.map { " · \($0.capitalized)" } ?? ""
        let org = auth.orgName.map { " · \($0)" } ?? ""
        let account = auth.email ?? String(localized: "your account")
        return String(localized: "Signed in as \(account)") + plan + org
    }

    private var statusColor: Color {
        guard claude.isAvailable, let auth = claude.auth else { return claude.checkingAuth ? .yellow : .red }
        return auth.loggedIn ? .green : .orange
    }

    private var folderLabel: String {
        let path = claude.workingDirectory.path
        return (path as NSString).abbreviatingWithTildeInPath
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = claude.workingDirectory
        panel.prompt = String(localized: "Use as brain")
        if panel.runModal() == .OK, let url = panel.url {
            state.brainVaultPath = url.path
        }
    }
}
#endif
