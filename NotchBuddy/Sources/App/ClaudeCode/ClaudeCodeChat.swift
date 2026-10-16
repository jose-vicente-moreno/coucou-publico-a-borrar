#if !APPSTORE
import Foundation
import Combine

/// The "Claude Code" chat provider: Mochi's chat runs through the user's own
/// `claude` CLI, signed in with their Claude account, inside the folder chosen in
/// Settings (their "brain"). That folder's CLAUDE.md, skills and agents come
/// along; read-only tools run freely and anything else asks in the notch.
@MainActor
final class ClaudeCodeChat: ObservableObject {
    static let shared = ClaudeCodeChat()

    /// Aliases the CLI resolves to the newest model the account may use.
    static let models: [(id: String, label: String)] = [
        ("opus", "Opus"), ("sonnet", "Sonnet"), ("haiku", "Haiku"),
    ]

    /// Never ask for these: looking things up in the brain is the whole point.
    static let readOnlyTools = ["Read", "Grep", "Glob", "WebSearch", "TodoWrite"]

    /// Always ask for these, whatever allow rules the user's settings carry: `ask`
    /// beats `allow` in Claude Code. A note, a dropped file or a web page can carry a
    /// prompt injection, and commands, writes and fetched URLs are how data leaves.
    static let alwaysAsk = ["Bash", "Write", "Edit", "MultiEdit", "NotebookEdit", "WebFetch"]

    /// The user's settings and the brain's project settings (its hooks, skills,
    /// plugins), not the folder's settings.local.json, which collects allow rules
    /// granted over time in the terminal.
    static let settingSources = ["user", "project"]

    static var brainSettingsJSON: String {
        let object: [String: Any] = ["permissions": ["ask": alwaysAsk]]
        let data = (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }

    static let brainPrompt = """
    You are Mochi, a small assistant living in the notch of the user's Mac. You run as \
    Claude Code inside the user's notes folder (their "brain"); its CLAUDE.md, commands, \
    skills and agents describe how it works. Whenever the answer may be in it, look it up \
    first (search and read the notes, or use the search commands and agents it provides) \
    and name the notes you used. Replies show in a small notch window: answer in the \
    user's language, keep it short, light Markdown only (bullets, **bold**, `code`), no \
    tables or big headings. Writing files or running commands needs the user's approval \
    in the notch: only do it when the user asked for it. Don't start routines its \
    instructions run at the beginning of a session: just answer the request.
    """

    @Published private(set) var executable: URL? = ClaudeCodeLocator.executable()
    @Published private(set) var auth: ClaudeCodeLocator.AuthStatus?
    @Published private(set) var checkingAuth = false

    var isAvailable: Bool { executable != nil }
    /// A brain turn is running (streaming or waiting for an approval).
    @Published private(set) var isBusy = false

    private var brain: ClaudeCodeSession?
    /// Turns sent in the current conversation (window/file context goes with the first).
    private var turnsInConversation = 0

    private static let logURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/NotchBuddy/claude-code-chat.log")

    // MARK: - Status

    func refresh() async {
        executable = ClaudeCodeLocator.executable()
        guard let executable else { auth = nil; return }
        checkingAuth = true
        auth = await ClaudeCodeLocator.authStatus(executable: executable)
        checkingAuth = false
    }

    /// The brain folder from Settings, or the home folder when unset or gone.
    var workingDirectory: URL {
        let path = (AppState.shared.brainVaultPath as NSString).expandingTildeInPath
        var isDirectory: ObjCBool = false
        if !path.isEmpty, FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue {
            return URL(fileURLWithPath: path)
        }
        return FileManager.default.homeDirectoryForCurrentUser
    }

    // MARK: - Conversation

    /// App quitting: end the brain session cleanly (its SessionEnd hooks run).
    func shutdown() {
        brain?.stop()
        brain = nil
    }

    /// New conversation: the next message starts a fresh Claude Code session.
    func reset() {
        brain?.reset()
        turnsInConversation = 0
    }

    func chat(query: String, context: PromptContext?, state: AppState) async {
        guard let executable = executable ?? ClaudeCodeLocator.executable() else {
            showError(ClaudeCodeError.notInstalled.localizedDescription, state: state)
            return
        }
        let session = brainSession(executable: executable)

        var content: [[String: Any]] = []
        if turnsInConversation == 0, let context {
            content += contextBlocks(context)
        }
        content.append(["type": "text", "text": query])
        guard let line = ClaudeCodeStream.userMessageLine(content: content) else {
            showError("Couldn't prepare the message.", state: state)
            return
        }

        isBusy = true
        defer { isBusy = false }
        let placeholder = ChatMessage(role: .assistant, content: "")
        let messageId = placeholder.id
        state.chatHistory.append(placeholder)
        state.stateOverride = .thinking
        let relay = StreamRelay(state: state, messageId: messageId)

        do {
            let result = try await session.send(line, timeout: 300) { event in
                // Keep the order of events: main queue, not one Task per event.
                DispatchQueue.main.async { MainActor.assumeIsolated { relay.handle(event) } }
            }
            turnsInConversation += 1
            var text = result.text.isEmpty ? relay.streamed : result.text
            if !result.deniedTools.isEmpty {
                let tools = Set(result.deniedTools).sorted().joined(separator: ", ")
                text += (text.isEmpty ? "" : "\n\n") + "_\(String(localized: "Not allowed")): \(tools)_"
            }
            if let index = state.chatHistory.firstIndex(where: { $0.id == messageId }) {
                state.chatHistory[index].content = text
            }
            state.stateOverride = nil
            state.view = .prompt
            NotificationCenter.default.post(name: .triggerEmote, object: result.isError ? BotEmote.annoyed : BotEmote.happy)
        } catch ClaudeCodeError.cancelled {
            // New chat while answering: nothing to report.
            state.chatHistory.removeAll { $0.id == messageId }
            state.stateOverride = nil
        } catch {
            state.chatHistory.removeAll { $0.id == messageId }
            showError(error.localizedDescription, state: state)
        }
    }

    // MARK: - Helpers

    /// One session per conversation; a new model or folder starts a new process
    /// but keeps the conversation (it resumes the same Claude Code session).
    private func brainSession(executable: URL) -> ClaudeCodeSession {
        let profile = ClaudeCodeProfile(
            model: AppState.shared.claudeCodeModel,
            workingDirectory: workingDirectory,
            systemPrompt: .append(Self.brainPrompt),
            allowedTools: Self.readOnlyTools,
            disallowedTools: ["AskUserQuestion"],
            settingSources: Self.settingSources,
            settingsJSON: Self.brainSettingsJSON,
            permissionMode: "default",
            environment: ["COUCOU_BRAIN": "1"])
        if let brain, brain.profile == profile { return brain }
        // Claude Code keeps sessions per folder: only the same folder can resume.
        let carried = brain?.profile.workingDirectory == profile.workingDirectory ? brain?.sessionId : nil
        brain?.stop()
        let session = ClaudeCodeSession(executable: executable, profile: profile,
                                        logURL: Self.logURL, resumeSessionId: carried)
        brain = session
        return session
    }

    private func contextBlocks(_ context: PromptContext) -> [[String: Any]] {
        switch context {
        case .window(let app, let title, let url):
            var text = "Context — App: \(app), Window: \(title)"
            if let url { text += ", URL: \(url)" }
            return [["type": "text", "text": text]]
        case .file(let name, let fileURL):
            var blocks: [[String: Any]] = []
            if let fileURL, let block = ClaudeService.shared.readFileAsBlock(url: fileURL) {
                blocks.append(block)
            }
            let path = fileURL.map { " (\($0.path))" } ?? ""
            blocks.append(["type": "text", "text": "File: \(name)\(path)"])
            return blocks
        }
    }

    private func showError(_ message: String, state: AppState) {
        state.stateOverride = .error
        state.noteMessage = message
        state.view = .note
    }
}

/// Turns stream events into the growing assistant bubble.
@MainActor
private final class StreamRelay {
    private let state: AppState
    private let messageId: UUID
    private(set) var streamed = ""

    init(state: AppState, messageId: UUID) {
        self.state = state
        self.messageId = messageId
    }

    func handle(_ event: ClaudeCodeEvent) {
        switch event {
        case .textBlockStarted:
            // Text before and after a tool call are separate paragraphs.
            if !streamed.isEmpty, !streamed.hasSuffix("\n\n") { streamed += "\n\n" }
        case .textDelta(let text):
            streamed += text
            if state.stateOverride == .thinking, !streamed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                state.stateOverride = nil   // typing dots off on the first visible text
            }
            if let index = state.chatHistory.firstIndex(where: { $0.id == messageId }) {
                state.chatHistory[index].content = streamed
            }
        default:
            break
        }
    }
}
#endif
