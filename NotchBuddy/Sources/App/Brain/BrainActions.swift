#if !APPSTORE
import AppKit

/// What the Brain card and the drop flow do: talk to the brain through the
/// Claude Code chat, open the vault, capture a dropped file into its inbox.
@MainActor
enum BrainActions {
    /// Text the chat's field starts with next time it opens (read once).
    private static var pendingDraft: String?

    /// The pending draft, cleared.
    static func takeDraft() -> String? {
        defer { pendingDraft = nil }
        return pendingDraft
    }
    /// How long the "saved" note stays before the island folds.
    private static let toastSeconds: TimeInterval = 3

    /// Opens the chat on the Claude Code provider (it runs in the brain folder),
    /// optionally with `draft` already typed.
    static func openChat(draft: String? = nil) {
        pendingDraft = draft
        switchChatProvider(.claudeCode)
        if let draft { NotificationCenter.default.post(name: .islandChatDraft, object: draft) }
    }

    /// Sends `query` to the brain chat the way PromptView.sendMessage() does. A
    /// card action is about the vault, not the window last attached: no context.
    static func ask(_ query: String) {
        let state = AppState.shared
        openChat()
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        // A reply still coming: the chat is open, the user can send it after.
        guard !query.isEmpty, state.stateOverride != .thinking, !ClaudeCodeChat.shared.isBusy else { return }
        state.chatHistory.append(ChatMessage(role: .user, content: query))
        state.stateOverride = .thinking
        Task {
            await ClaudeService.shared.chat(query: query, context: nil, state: state)
            // A command may have changed what the counters count.
            BrainController.shared.pollNow()
        }
    }

    /// A counter's button, as the brain's config describes it.
    static func run(_ action: BrainConfig.Action) {
        switch action.effect {
        case .send(let message): ask(message)
        case .draft(let text): openChat(draft: text)
        }
    }

    static func openObsidian() {
        guard let vault = BrainController.shared.vaultURL else { openSettings(); return }
        if let url = BrainVault.obsidianURL(for: vault) { NSWorkspace.shared.open(url) }
    }

    /// A service's page (only http/https URLs get this far).
    static func open(_ service: BrainStatus.Service) {
        if let url = service.open { NSWorkspace.shared.open(url) }
    }

    /// Settings → Chat, where the brain folder is chosen.
    static func openSettings() {
        NotificationCenter.default.post(name: .openFullSettings, object: "chat")
    }

    // MARK: - Save to brain

    /// The file just dropped on the notch, as a new note in the brain's inbox.
    static func saveDroppedFile() {
        let state = AppState.shared
        guard let file = state.droppedFile else { return }
        guard let vault = BrainController.shared.vaultURL else {
            showToast(String(localized: "Choose your brain folder in Settings → Chat first."), failed: true)
            return
        }
        state.noteMessage = String(localized: "Saving to brain…")
        state.view = .note
        let source = file.url
        let name = file.name
        Task {
            // Copying a big file must not hold up the main thread.
            let result = await Task.detached(priority: .userInitiated) {
                Result {
                    try BrainInbox.save(fileURL: source, name: name, vault: vault,
                                        inbox: BrainConfig.load(vault: vault).inbox)
                }
            }.value
            switch result {
            case .success:
                showToast(String(localized: "Saved to brain inbox"), failed: false)
            case .failure(let error):
                showToast(String(format: String(localized: "Couldn't save to brain: %@"), error.localizedDescription),
                          failed: true)
            }
            BrainController.shared.pollNow()
        }
    }

    private static func showToast(_ message: String, failed: Bool) {
        let state = AppState.shared
        SoundEngine.shared.play(failed ? "error" : "send")
        NotificationCenter.default.post(name: .triggerEmote, object: failed ? BotEmote.annoyed : BotEmote.happy)
        state.noteMessage = message
        state.view = .note
        DispatchQueue.main.asyncAfter(deadline: .now() + toastSeconds) {
            NotificationCenter.default.post(name: .islandCollapse, object: nil)
        }
    }
}
#endif

#if !APPSTORE
extension Notification.Name {
    /// A draft for the chat field when the chat is already on screen (object: String).
    static let islandChatDraft = Notification.Name("notchBuddy.islandChatDraft")
}
#endif
