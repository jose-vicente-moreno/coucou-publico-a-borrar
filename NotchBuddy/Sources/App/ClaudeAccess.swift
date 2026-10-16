import Foundation

/// Who answers the features that use a Claude model besides the chat (Flow clean-up,
/// Notetaker summaries, the voice assistant): an Anthropic API key, or — GitHub build
/// only — the user's own Claude Code CLI and Claude login, with no key at all.
enum ClaudeAccess {
    static var hasAPIKey: Bool {
        !(KeychainStore.shared.get("anthropic-api-key") ?? "").isEmpty
    }

    static var claudeCodeInstalled: Bool {
        #if !APPSTORE
        ClaudeCodeLocator.executable() != nil
        #else
        false
        #endif
    }

    /// Claude Code takes over when it is installed and either no key is set or the
    /// chat itself is set to Claude Code.
    static var usesClaudeCode: Bool {
        claudeCodeInstalled && (!hasAPIKey
            || UserDefaults.standard.string(forKey: "chatProvider") == ChatProvider.claudeCode.rawValue)
    }

    static var isAvailable: Bool { hasAPIKey || claudeCodeInstalled }
}
