#if !APPSTORE
import Foundation

// The Claude Code provider talks to the user's own, unmodified `claude` CLI in
// print mode with stream-json on both sides. The CLI signs in with the user's
// Claude account (claude.ai or Console), so Coucou never sees a key or token.

/// What Coucou needs from one line of `claude -p --output-format stream-json`.
enum ClaudeCodeEvent: Equatable, Sendable {
    case initialized(sessionId: String)
    /// A text block of the top-level assistant starts (not a sub-agent's).
    case textBlockStarted
    case textDelta(String)
    /// The assistant starts calling a tool (name only, for the "thinking" caption).
    case toolStarted(String)
    case turnFinished(ClaudeCodeTurnResult)
    case ignored
}

struct ClaudeCodeTurnResult: Equatable, Sendable {
    let text: String
    let isError: Bool
    let sessionId: String?
    let deniedTools: [String]
}

enum ClaudeCodeStream {

    static func parse(_ line: String) -> ClaudeCodeEvent {
        guard let data = line.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else { return .ignored }
        switch type {
        case "system":
            guard json["subtype"] as? String == "init", let id = json["session_id"] as? String else { return .ignored }
            return .initialized(sessionId: id)
        case "stream_event":
            // Events from inside a sub-agent carry the Task call that spawned it.
            if let parent = json["parent_tool_use_id"] as? String, !parent.isEmpty { return .ignored }
            return parseStreamEvent(json["event"] as? [String: Any] ?? [:])
        case "result":
            let denials = (json["permission_denials"] as? [[String: Any]] ?? []).compactMap { $0["tool_name"] as? String }
            // `is_error` is not always set: a run that stopped on its turn limit
            // reports `subtype: error_max_turns` and nothing else, and taking that
            // as a success would show the user a blank answer and call it fine.
            let subtype = json["subtype"] as? String ?? "success"
            let flagged = json["is_error"] as? Bool ?? false
            return .turnFinished(ClaudeCodeTurnResult(
                text: (json["result"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
                isError: flagged || subtype != "success",
                sessionId: json["session_id"] as? String,
                deniedTools: denials))
        default:
            return .ignored
        }
    }

    private static func parseStreamEvent(_ event: [String: Any]) -> ClaudeCodeEvent {
        switch event["type"] as? String {
        case "content_block_delta":
            guard let delta = event["delta"] as? [String: Any], delta["type"] as? String == "text_delta",
                  let text = delta["text"] as? String else { return .ignored }
            return .textDelta(text)
        case "content_block_start":
            let block = event["content_block"] as? [String: Any] ?? [:]
            switch block["type"] as? String {
            case "text": return .textBlockStarted
            case "tool_use", "server_tool_use":
                return .toolStarted(block["name"] as? String ?? "tool")
            default: return .ignored
            }
        default:
            return .ignored
        }
    }

    /// One stdin line for `--input-format stream-json`: a user turn made of
    /// Messages API content blocks (text, image, document).
    static func userMessageLine(content: [[String: Any]]) -> String? {
        let envelope: [String: Any] = [
            "type": "user",
            "message": ["role": "user", "content": content],
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: envelope) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

// MARK: - Profile → CLI arguments

/// How one `claude` process is started. A profile is fixed for the life of a
/// session; changing the model or folder means a new session.
struct ClaudeCodeProfile: Equatable, Sendable {
    enum SystemPrompt: Equatable, Sendable {
        /// Added after Claude Code's own prompt (keeps CLAUDE.md, skills, tools).
        case append(String)
        /// Replaces it entirely (small, fast one-purpose runs).
        case replace(String)
    }

    var model: String
    var workingDirectory: URL
    var systemPrompt: SystemPrompt
    /// nil keeps Claude Code's built-in tool set; [] disables every tool.
    var tools: [String]? = nil
    /// Tools that never ask for permission. Anything else goes through the
    /// PermissionRequest hook (the Allow / Deny card in the notch).
    var allowedTools: [String] = []
    /// Tools removed from the session (e.g. AskUserQuestion: nobody can answer it
    /// in print mode).
    var disallowedTools: [String] = []
    /// false loads only the working folder's project settings, so the user's
    /// global hooks (and Coucou's own) stay out of utility runs.
    var loadUserSettings: Bool = true
    /// Explicit `--setting-sources` (e.g. ["user", "project"] leaves out the folder's
    /// settings.local.json). Wins over `loadUserSettings`.
    var settingSources: [String]? = nil
    /// `--settings` JSON layered on top (e.g. `permissions.ask`, which beats any allow rule).
    var settingsJSON: String? = nil
    /// `--permission-mode`, pinned so a settings file can't switch to acceptEdits/bypass.
    var permissionMode: String? = nil
    /// nil means no MCP server at all; plugin servers are always skipped
    /// because they add seconds to every start.
    var mcpConfigJSON: String? = nil
    var persistSession: Bool = true
    var disableSlashCommands: Bool = false
    var environment: [String: String] = [:]

    func arguments(resume: String?) -> [String] {
        var args = ["-p",
                    "--input-format", "stream-json",
                    "--output-format", "stream-json",
                    "--verbose",
                    "--include-partial-messages",
                    "--model", model]
        switch systemPrompt {
        case .append(let text) where !text.isEmpty: args += ["--append-system-prompt", text]
        case .append: break
        case .replace(let text): args += ["--system-prompt", text]
        }
        if let tools { args += ["--tools", tools.joined(separator: ",")] }
        if !allowedTools.isEmpty { args += ["--allowedTools", allowedTools.joined(separator: ",")] }
        if !disallowedTools.isEmpty { args += ["--disallowedTools", disallowedTools.joined(separator: ",")] }
        if let settingSources { args += ["--setting-sources", settingSources.joined(separator: ",")] }
        else if !loadUserSettings { args += ["--setting-sources", "project"] }
        if let settingsJSON { args += ["--settings", settingsJSON] }
        if let permissionMode { args += ["--permission-mode", permissionMode] }
        args += ["--strict-mcp-config", "--mcp-config", mcpConfigJSON ?? #"{"mcpServers":{}}"#]
        if !persistSession { args.append("--no-session-persistence") }
        if disableSlashCommands { args.append("--disable-slash-commands") }
        if persistSession, let resume { args += ["--resume", resume] }
        return args
    }
}
#endif
