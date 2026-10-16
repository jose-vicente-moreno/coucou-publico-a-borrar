#if !APPSTORE
import Foundation

/// Short one-purpose requests (Flow clean-up, note summaries, voice web answers)
/// through the user's Claude Code login. Each purpose keeps one warm process: the
/// first request pays the CLI's start-up, the next ones only the model. A process is
/// replaced when its instructions change, and every `maxTurns` requests so earlier
/// requests don't pile up in its context.
///
/// Utility runs load no user settings (no hooks, no CLAUDE.md, no session saved): they
/// start in an empty folder of the app's own.
final class ClaudeCodeUtility: @unchecked Sendable {
    static let shared = ClaudeCodeUtility()

    enum Purpose: String, Sendable {
        case flowCleanup, noteSummary, voiceWeb
    }

    private let lock = NSLock()
    private var sessions: [Purpose: (session: ClaudeCodeSession, turns: Int)] = [:]
    /// Earlier requests stay in the warm process's context: keep few.
    private let maxTurns = 5

    static let workingDirectory: URL = {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/NotchBuddy/claude-utility", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    /// Text of Claude's answer to `text` under `system`. `fresh` uses a new
    /// process and drops it afterwards (one-off requests such as a long transcript).
    func complete(_ purpose: Purpose, system: String, text: String, model: String = "haiku",
                  tools: [String] = [], timeout: TimeInterval, fresh: Bool = false) async throws -> String {
        guard let executable = ClaudeCodeLocator.executable() else { throw ClaudeCodeError.notInstalled }
        let profile = ClaudeCodeProfile(
            model: model, workingDirectory: Self.workingDirectory,
            systemPrompt: .replace(system), tools: tools, allowedTools: tools,
            loadUserSettings: false, persistSession: false, disableSlashCommands: true)
        let session = take(purpose, profile: profile, executable: executable, fresh: fresh)
        guard let line = ClaudeCodeStream.userMessageLine(content: [["type": "text", "text": text]]) else {
            throw ClaudeCodeError.writeFailed
        }
        defer { if fresh { session.stop() } }
        let result = try await session.send(line, timeout: timeout) { _ in }
        if result.isError { throw ClaudeCodeError.exited(1, result.text) }
        return result.text
    }

    /// Ends every warm process (e.g. when the app quits).
    func stopAll() {
        let all = lock.withLock { () -> [ClaudeCodeSession] in
            defer { sessions.removeAll() }
            return sessions.values.map(\.session)
        }
        all.forEach { $0.stop() }
    }

    private func take(_ purpose: Purpose, profile: ClaudeCodeProfile, executable: URL, fresh: Bool) -> ClaudeCodeSession {
        let logURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/NotchBuddy/claude-code-\(purpose.rawValue).log")
        if fresh {
            return ClaudeCodeSession(executable: executable, profile: profile, logURL: logURL, idleTimeout: 60)
        }
        let (session, stale) = lock.withLock { () -> (ClaudeCodeSession, ClaudeCodeSession?) in
            if let current = sessions[purpose], current.session.profile == profile, current.turns < maxTurns {
                sessions[purpose] = (current.session, current.turns + 1)
                return (current.session, nil)
            }
            let fresh = ClaudeCodeSession(executable: executable, profile: profile, logURL: logURL, idleTimeout: 180)
            let old = sessions[purpose]?.session
            sessions[purpose] = (fresh, 1)
            return (fresh, old)
        }
        stale?.stop()
        return session
    }
}
#endif
