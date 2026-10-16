import Foundation

/// Parser, argument builder and process session for the Claude Code provider.
/// Run with scripts/test-claude-code.sh (needs tests/fake_claude.py).
@main
enum ClaudeCodeTests {
    static func main() async {
        var cases = 0
        func check(_ name: String, _ condition: Bool, _ detail: @autoclosure () -> String = "") {
            precondition(condition, "\(name) failed \(detail())")
            cases += 1
        }

        // MARK: Stream parsing

        check("init carries the session id",
              ClaudeCodeStream.parse(#"{"type":"system","subtype":"init","session_id":"abc"}"#)
                == .initialized(sessionId: "abc"))
        check("top-level text delta",
              ClaudeCodeStream.parse(#"{"type":"stream_event","parent_tool_use_id":null,"event":{"type":"content_block_delta","delta":{"type":"text_delta","text":"Hi"}}}"#)
                == .textDelta("Hi"))
        check("sub-agent delta is ignored",
              ClaudeCodeStream.parse(#"{"type":"stream_event","parent_tool_use_id":"toolu_1","event":{"type":"content_block_delta","delta":{"type":"text_delta","text":"x"}}}"#)
                == .ignored)
        check("tool use start names the tool",
              ClaudeCodeStream.parse(#"{"type":"stream_event","event":{"type":"content_block_start","content_block":{"type":"tool_use","name":"Grep"}}}"#)
                == .toolStarted("Grep"))
        check("text block start",
              ClaudeCodeStream.parse(#"{"type":"stream_event","event":{"type":"content_block_start","content_block":{"type":"text","text":""}}}"#)
                == .textBlockStarted)
        check("successful result",
              ClaudeCodeStream.parse(#"{"type":"result","subtype":"success","is_error":false,"session_id":"s1","result":"Done","permission_denials":[]}"#)
                == .turnFinished(ClaudeCodeTurnResult(text: "Done", isError: false, sessionId: "s1", deniedTools: [])))
        check("error result lists denied tools",
              ClaudeCodeStream.parse(#"{"type":"result","subtype":"success","is_error":true,"session_id":"s1","result":"No","permission_denials":[{"tool_name":"Write"}]}"#)
                == .turnFinished(ClaudeCodeTurnResult(text: "No", isError: true, sessionId: "s1", deniedTools: ["Write"])))
        check("result without text (error_max_turns)",
              ClaudeCodeStream.parse(#"{"type":"result","subtype":"error_max_turns","is_error":true,"session_id":"s1"}"#)
                == .turnFinished(ClaudeCodeTurnResult(text: "", isError: true, sessionId: "s1", deniedTools: [])))
        check("garbage is ignored", ClaudeCodeStream.parse("not json") == .ignored)
        check("assistant snapshot is ignored (deltas carry the text)",
              ClaudeCodeStream.parse(#"{"type":"assistant","message":{"content":[]}}"#) == .ignored)

        let line = ClaudeCodeStream.userMessageLine(content: [["type": "text", "text": "hola"]])
        let decoded = line.flatMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any] }
        let message = decoded?["message"] as? [String: Any]
        check("user message envelope", decoded?["type"] as? String == "user" && message?["role"] as? String == "user")
        check("user message is a single line", line.map { !$0.contains("\n") } ?? false)

        // MARK: Arguments

        let vault = URL(fileURLWithPath: "/tmp/vault")
        let brain = ClaudeCodeProfile(model: "sonnet", workingDirectory: vault,
                                      systemPrompt: .append("Be Mochi."),
                                      allowedTools: ["Read", "Grep"], disallowedTools: ["AskUserQuestion"])
        let brainArgs = brain.arguments(resume: nil)
        func has(_ args: [String], _ flag: String, _ value: String? = nil) -> Bool {
            guard let i = args.firstIndex(of: flag) else { return false }
            guard let value else { return true }
            return i + 1 < args.count && args[i + 1] == value
        }
        check("print mode", brainArgs.first == "-p")
        check("stream-json in", has(brainArgs, "--input-format", "stream-json"))
        check("stream-json out", has(brainArgs, "--output-format", "stream-json"))
        check("verbose (required by stream-json)", has(brainArgs, "--verbose"))
        check("partial messages", has(brainArgs, "--include-partial-messages"))
        check("model", has(brainArgs, "--model", "sonnet"))
        check("appended system prompt", has(brainArgs, "--append-system-prompt", "Be Mochi."))
        check("pre-approved tools", has(brainArgs, "--allowedTools", "Read,Grep"))
        check("removed tools", has(brainArgs, "--disallowedTools", "AskUserQuestion"))
        check("brain keeps user settings", !has(brainArgs, "--setting-sources"))
        check("brain keeps the default tool set", !has(brainArgs, "--tools"))
        check("plugin MCP servers are skipped", has(brainArgs, "--strict-mcp-config"))
        check("no resume on a fresh session", !has(brainArgs, "--resume"))
        check("resume after a restart", has(brain.arguments(resume: "s-9"), "--resume", "s-9"))

        let utility = ClaudeCodeProfile(model: "haiku", workingDirectory: vault,
                                        systemPrompt: .replace("Clean it."), tools: [],
                                        loadUserSettings: false, persistSession: false,
                                        disableSlashCommands: true)
        let utilityArgs = utility.arguments(resume: nil)
        check("utility replaces the system prompt", has(utilityArgs, "--system-prompt", "Clean it."))
        check("utility has no tools", has(utilityArgs, "--tools", ""))
        check("utility skips user hooks and settings", has(utilityArgs, "--setting-sources", "project"))
        check("utility does not persist", has(utilityArgs, "--no-session-persistence"))
        check("utility disables slash commands", has(utilityArgs, "--disable-slash-commands"))
        check("utility never resumes", !has(utility.arguments(resume: "s-1"), "--resume"))

        var strict = brain
        strict.settingSources = ["user", "project"]
        strict.settingsJSON = #"{"permissions":{"ask":["Bash"]}}"#
        strict.permissionMode = "default"
        let strictArgs = strict.arguments(resume: nil)
        check("explicit setting sources", has(strictArgs, "--setting-sources", "user,project"))
        check("extra settings layered", has(strictArgs, "--settings", #"{"permissions":{"ask":["Bash"]}}"#))
        check("permission mode pinned", has(strictArgs, "--permission-mode", "default"))

        let mcp = ClaudeCodeProfile(model: "haiku", workingDirectory: vault, systemPrompt: .append(""),
                                    mcpConfigJSON: #"{"mcpServers":{"coucou":{}}}"#)
        check("mcp config is passed", has(mcp.arguments(resume: nil), "--mcp-config", #"{"mcpServers":{"coucou":{}}}"#))
        check("empty appended prompt is omitted", !has(mcp.arguments(resume: nil), "--append-system-prompt"))

        // MARK: Environment

        let env = ClaudeCodeLocator.environment(executable: URL(fileURLWithPath: "/opt/x/bin/claude"),
                                                base: ["PATH": "/usr/bin", "CLAUDECODE": "1",
                                                       "CLAUDE_CODE_ENTRYPOINT": "cli", "HOME": "/Users/u"],
                                                extra: ["COUCOU_BRAIN": "1"])
        check("binary folder leads PATH", env["PATH"]?.hasPrefix("/opt/x/bin:") ?? false, env["PATH"] ?? "nil")
        check("nested-session markers removed", env["CLAUDECODE"] == nil && env["CLAUDE_CODE_ENTRYPOINT"] == nil)
        check("extra variables applied", env["COUCOU_BRAIN"] == "1")

        // MARK: Session against the fake CLI

        guard CommandLine.arguments.count > 1 else {
            print("ClaudeCodeTests: \(cases) cases passed (session tests skipped: no fake path)")
            return
        }
        let fake = URL(fileURLWithPath: CommandLine.arguments[1])
        let workDir = URL(fileURLWithPath: NSTemporaryDirectory())
        let profile = ClaudeCodeProfile(model: "fake", workingDirectory: workDir, systemPrompt: .append("x"),
                                        environment: ["COUCOU_TEST_ENV": "brain"])
        let session = ClaudeCodeSession(executable: fake, profile: profile, logURL: nil)
        let collector = EventCollector()

        func send(_ text: String, timeout: TimeInterval = 10) async -> Result<ClaudeCodeTurnResult, Error> {
            let line = ClaudeCodeStream.userMessageLine(content: [["type": "text", "text": text]])!
            do { return .success(try await session.send(line, timeout: timeout) { collector.add($0) }) }
            catch { return .failure(error) }
        }
        func fields(_ result: Result<ClaudeCodeTurnResult, Error>) -> [String: String] {
            guard case .success(let r) = result else { return [:] }
            var out: [String: String] = [:]
            for part in r.text.split(separator: "|").dropFirst() {
                let kv = part.split(separator: "=", maxSplits: 1).map(String.init)
                if kv.count == 2 { out[kv[0]] = kv[1] }
            }
            return out
        }

        let first = await send("hola")
        let f1 = fields(first)
        check("first turn answers", f1["turn"] == "1", "\(first)")
        check("fresh process has no resume", f1["resume"] == "none")
        check("profile environment reaches the process", f1["env"] == "brain")
        check("session id captured", session.sessionId == "sess-fake-123")
        check("deltas streamed in order", collector.deltas() == ["Hola", " mundo"], "\(collector.deltas())")

        let second = await send("otra")
        let f2 = fields(second)
        check("same process for the next turn", f2["pid"] == f1["pid"] && f2["turn"] == "2", "\(f1) \(f2)")

        collector.clear()
        _ = await send("TOOL")
        check("tool start surfaced", collector.tools() == ["Read"], "\(collector.tools())")
        check("sub-agent text filtered", !collector.deltas().contains("sub-agent noise"))

        if case .success(let denied) = await send("DENY") {
            check("denial reported", denied.isError && denied.deniedTools == ["Write"])
        } else { check("denial turn completes", false) }

        let slow = await send("SLOW", timeout: 1)
        if case .failure(let error as ClaudeCodeError) = slow { check("slow turn times out", error == .timeout) }
        else { check("slow turn times out", false, "\(slow)") }
        let afterTimeout = fields(await send("hola"))
        check("restart resumes the conversation", afterTimeout["resume"] == "sess-fake-123", "\(afterTimeout)")
        check("restart is a new process", afterTimeout["pid"] != f1["pid"])

        let crash = await send("CRASH")
        if case .failure(let error as ClaudeCodeError) = crash, case .exited(let status, _) = error {
            check("crash reports the exit status", status == 3)
        } else { check("crash reports the exit status", false, "\(crash)") }
        check("next turn after a crash works", fields(await send("hola"))["turn"] == "1")

        session.reset()
        check("reset forgets the conversation", session.sessionId == nil)
        check("new conversation does not resume", fields(await send("hola"))["resume"] == "none")

        async let a = send("SLOW", timeout: 2)
        try? await Task.sleep(nanoseconds: 200_000_000)
        let busy = await send("hola")
        if case .failure(let error as ClaudeCodeError) = busy { check("one turn at a time", error == .busy) }
        else { check("one turn at a time", false, "\(busy)") }
        _ = await a
        session.stop()
        check("stopped session is not running", !session.isRunning)

        let lastWords = await send("RESULT_THEN_EXIT")
        if case .success(let r) = lastWords { check("result printed just before exit still counts", r.text == "last words") }
        else { check("result printed just before exit still counts", false, "\(lastWords)") }

        let logURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("claude-code-tests-\(getpid()).log")
        let refused = ClaudeCodeSession(executable: fake, profile: profile, logURL: logURL, resumeSessionId: "bad-session")
        let refusedLine = ClaudeCodeStream.userMessageLine(content: [["type": "text", "text": "hola"]])!
        do {
            _ = try await refused.send(refusedLine, timeout: 10) { _ in }
            check("refused resume fails", false)
        } catch let error as ClaudeCodeError {
            if case .exited(1, let tail) = error { check("refused resume shows stderr", tail.contains("No conversation found"), tail) }
            else { check("refused resume exit status", false, "\(error)") }
        } catch { check("refused resume error type", false, "\(error)") }
        check("refused resume forgets the session", refused.sessionId == nil)
        let fresh = try? await refused.send(refusedLine, timeout: 10) { _ in }
        check("next turn starts a new conversation", fresh?.text.contains("resume=none") ?? false, fresh?.text ?? "nil")
        refused.stop()
        try? FileManager.default.removeItem(at: logURL)

        let carried = ClaudeCodeSession(executable: fake, profile: profile, logURL: nil, resumeSessionId: "sess-old")
        let carriedLine = ClaudeCodeStream.userMessageLine(content: [["type": "text", "text": "hola"]])!
        let carriedResult = try? await carried.send(carriedLine, timeout: 10) { _ in }
        check("a carried session id is resumed", carriedResult?.text.contains("resume=sess-old") ?? false,
              carriedResult?.text ?? "nil")
        carried.stop()

        print("ClaudeCodeTests: \(cases) cases passed")
    }
}

final class EventCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var events: [ClaudeCodeEvent] = []
    func add(_ event: ClaudeCodeEvent) { lock.withLock { events.append(event) } }
    func clear() { lock.withLock { events.removeAll() } }
    func deltas() -> [String] {
        lock.withLock { events.compactMap { if case .textDelta(let t) = $0 { t } else { nil } } }
    }
    func tools() -> [String] {
        lock.withLock { events.compactMap { if case .toolStarted(let t) = $0 { t } else { nil } } }
    }
}
