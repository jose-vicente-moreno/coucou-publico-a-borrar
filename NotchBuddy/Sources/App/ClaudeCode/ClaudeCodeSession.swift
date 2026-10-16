#if !APPSTORE
import Foundation

enum ClaudeCodeError: Error, Equatable, LocalizedError {
    case notInstalled
    case busy
    case launchFailed(String)
    case writeFailed
    case timeout
    case exited(Int32, String)
    case cancelled
    case outputTooLarge

    var errorDescription: String? {
        switch self {
        case .notInstalled: "Claude Code isn't installed. Install it, then sign in with `claude`."
        case .busy: "Claude is still answering the previous message."
        case .launchFailed(let why): "Couldn't start Claude Code: \(why)"
        case .writeFailed: "Couldn't send the message to Claude Code."
        case .timeout: "Claude Code took too long to answer."
        case .exited(let status, let tail):
            tail.isEmpty ? "Claude Code stopped (exit \(status))." : "Claude Code stopped (exit \(status)): \(tail)"
        case .cancelled: "Cancelled."
        case .outputTooLarge: "Claude Code sent an answer too large to read."
        }
    }
}

/// One long-lived `claude -p` process fed through stdin (stream-json). Paying the
/// CLI's start-up once per conversation keeps later turns at API latency.
///
/// - One turn at a time; a second `send` while one runs throws `.busy`.
/// - A timeout or crash kills the process; the next `send` starts a new one with
///   `--resume <session>`, so the conversation survives. A resume that fails before
///   the CLI starts forgets the session, so the next turn starts a new one.
/// - After `idleTimeout` without a turn the process is stopped (stdin closed, so
///   Claude Code ends the session normally and its SessionEnd hooks run).
final class ClaudeCodeSession: @unchecked Sendable {
    private let executable: URL
    let profile: ClaudeCodeProfile
    private let logURL: URL?
    private let idleTimeout: TimeInterval
    /// Writes and the final close of stdin, in order: a close never lands mid-write.
    private let writeQueue = DispatchQueue(label: "coucou.claude-code.stdin")
    /// Past this, one stdout line can't be a stream-json event we want.
    private static let maxBuffered = 64 * 1024 * 1024
    /// Grace for the last stdout chunk after the process exits (its `result` line).
    private static let drainDelay: TimeInterval = 0.3

    private let lock = NSLock()
    private var process: Process?
    private var stdin: FileHandle?
    private var generation = 0
    private var buffer = Data()
    private var currentSessionId: String?
    private var turn: Turn?
    private var turnCounter = 0
    private var idleToken = 0
    private var spawnResumed = false
    private var initializedSinceSpawn = false

    private struct Turn {
        let id: Int
        let onEvent: @Sendable (ClaudeCodeEvent) -> Void
        let continuation: CheckedContinuation<ClaudeCodeTurnResult, Error>
    }

    /// What a stop leaves to clean up outside the lock.
    private struct Detached {
        let process: Process?
        let stdin: FileHandle?
        let turn: Turn?
    }

    /// `resumeSessionId` continues an existing Claude Code conversation (e.g. the
    /// same chat after the model changed).
    init(executable: URL, profile: ClaudeCodeProfile, logURL: URL?,
         idleTimeout: TimeInterval = 600, resumeSessionId: String? = nil) {
        self.executable = executable
        self.profile = profile
        self.logURL = logURL
        self.idleTimeout = idleTimeout
        self.currentSessionId = resumeSessionId
    }

    deinit { process?.terminate() }

    var sessionId: String? { lock.withLock { currentSessionId } }
    var isRunning: Bool { lock.withLock { process?.isRunning ?? false } }

    /// Sends one user turn (`line` from `ClaudeCodeStream.userMessageLine`) and
    /// returns when Claude Code reports the turn's result. `onEvent` gets every
    /// event of the turn, off the main thread, in order.
    func send(_ line: String, timeout: TimeInterval,
              onEvent: @escaping @Sendable (ClaudeCodeEvent) -> Void) async throws -> ClaudeCodeTurnResult {
        try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            if turn != nil {
                lock.unlock()
                continuation.resume(throwing: ClaudeCodeError.busy)
                return
            }
            if process?.isRunning != true {
                do { try spawnLocked() } catch {
                    lock.unlock()
                    continuation.resume(throwing: ClaudeCodeError.launchFailed(error.localizedDescription))
                    return
                }
            }
            idleToken += 1   // a pending idle stop no longer applies
            turnCounter += 1
            let id = turnCounter
            turn = Turn(id: id, onEvent: onEvent, continuation: continuation)
            let handle = stdin
            lock.unlock()

            // Off the caller's thread: an attached PDF can be megabytes, and the pipe
            // only drains as fast as the CLI reads.
            writeQueue.async { [weak self] in
                do {
                    guard let handle else { throw ClaudeCodeError.writeFailed }
                    try handle.write(contentsOf: Data((line + "\n").utf8))
                } catch {
                    self?.kill(reason: .writeFailed, turnId: id)
                }
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { [weak self] in
                self?.kill(reason: .timeout, turnId: id)
            }
        }
    }

    /// Ends the process gracefully; the conversation can still be resumed.
    func stop() {
        let detached = lock.withLock { detachLocked() }
        finishStop(detached)
    }

    /// Stops and forgets the conversation: the next turn starts a new one.
    func reset() {
        let detached = lock.withLock { () -> Detached in
            currentSessionId = nil
            return detachLocked()
        }
        finishStop(detached)
    }

    // MARK: - Stopping

    /// Caller holds `lock`.
    private func detachLocked() -> Detached {
        let detached = Detached(process: process, stdin: stdin, turn: turn)
        process = nil
        stdin = nil
        turn = nil
        generation += 1
        idleToken += 1
        return detached
    }

    private func finishStop(_ detached: Detached) {
        detached.turn?.continuation.resume(throwing: ClaudeCodeError.cancelled)
        let handle = detached.stdin
        writeQueue.async { try? handle?.close() }
        guard let running = detached.process else { return }
        // EOF lets Claude Code close the session (SessionEnd hooks). Kill it if it lingers.
        DispatchQueue.global().asyncAfter(deadline: .now() + 5) {
            if running.isRunning { running.terminate() }
        }
    }

    private func scheduleIdleStopLocked() {
        idleToken += 1
        let token = idleToken
        DispatchQueue.global().asyncAfter(deadline: .now() + idleTimeout) { [weak self] in
            self?.stopIfIdle(token: token)
        }
    }

    /// The idle stop, checked under the lock: a turn started meanwhile wins.
    private func stopIfIdle(token: Int) {
        let detached = lock.withLock { () -> Detached? in
            guard token == idleToken, turn == nil, process != nil else { return nil }
            return detachLocked()
        }
        if let detached { finishStop(detached) }
    }

    // MARK: - Process

    /// Caller holds `lock`.
    private func spawnLocked() throws {
        let child = Process()
        child.executableURL = executable
        child.arguments = profile.arguments(resume: currentSessionId)
        child.currentDirectoryURL = profile.workingDirectory
        child.environment = ClaudeCodeLocator.environment(executable: executable, extra: profile.environment)

        let input = Pipe()
        let output = Pipe()
        // A write after the child died must fail with EPIPE, not kill the app.
        _ = fcntl(input.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
        child.standardInput = input
        child.standardOutput = output
        child.standardError = openLog() ?? FileHandle.nullDevice

        generation += 1
        let gen = generation
        buffer.removeAll()
        spawnResumed = profile.persistSession && currentSessionId != nil
        initializedSinceSpawn = false
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                return
            }
            self?.ingest(data, generation: gen)
        }
        child.terminationHandler = { [weak self] finished in
            let status = finished.terminationStatus
            guard let session = self else { return }
            // Let the readability handler deliver the last lines (a final `result`) first.
            DispatchQueue.global().asyncAfter(deadline: .now() + ClaudeCodeSession.drainDelay) { [weak session] in
                session?.ended(status: status, generation: gen)
            }
        }
        try child.run()
        process = child
        stdin = input.fileHandleForWriting
    }

    private func openLog() -> FileHandle? {
        guard let logURL else { return nil }
        try? FileManager.default.createDirectory(at: logURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: logURL.path, contents: nil)
        return try? FileHandle(forWritingTo: logURL)
    }

    /// The last bytes of stderr, for the error message.
    private func logTail() -> String {
        guard let logURL, let handle = try? FileHandle(forReadingFrom: logURL) else { return "" }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        try? handle.seek(toOffset: size > 300 ? size - 300 : 0)
        let data = (try? handle.readToEnd()) ?? Data()
        return String(decoding: data, as: UTF8.self)
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespaces)
    }

    private func ingest(_ data: Data, generation gen: Int) {
        lock.lock()
        guard gen == generation else { lock.unlock(); return }
        let scanned = buffer.count   // bytes already searched for a newline
        buffer.append(data)
        var lines: [String] = []
        var lineStart = buffer.startIndex
        var cursor = buffer.startIndex + scanned
        while let newline = buffer[cursor...].firstIndex(of: 0x0A) {
            lines.append(String(decoding: buffer[lineStart..<newline], as: UTF8.self))
            lineStart = newline + 1
            cursor = lineStart
        }
        if lineStart > buffer.startIndex { buffer.removeSubrange(buffer.startIndex..<lineStart) }
        let overflow = buffer.count > Self.maxBuffered
        let active = turn
        lock.unlock()

        for line in lines where !line.isEmpty {
            let event = ClaudeCodeStream.parse(line)
            switch event {
            case .ignored:
                continue
            case .initialized(let id):
                lock.withLock {
                    if gen == generation { initializedSinceSpawn = true }
                    currentSessionId = id
                }
                active?.onEvent(event)
            case .turnFinished(let result):
                if let id = result.sessionId { lock.withLock { currentSessionId = id } }
                active?.onEvent(event)
                if let active { finish(turnId: active.id, with: .success(result)) }
            default:
                active?.onEvent(event)
            }
        }
        if overflow, let active { kill(reason: .outputTooLarge, turnId: active.id) }
    }

    private func finish(turnId: Int, with result: Result<ClaudeCodeTurnResult, Error>) {
        lock.lock()
        guard let active = turn, active.id == turnId else { lock.unlock(); return }
        turn = nil
        if case .success = result { scheduleIdleStopLocked() }
        lock.unlock()
        active.continuation.resume(with: result)
    }

    /// Kills the process when the turn `turnId` is still the one running.
    private func kill(reason: ClaudeCodeError, turnId: Int) {
        lock.lock()
        guard let active = turn, active.id == turnId else { lock.unlock(); return }
        let running = process
        process = nil
        stdin = nil
        turn = nil
        generation += 1
        lock.unlock()
        running?.terminate()
        active.continuation.resume(throwing: reason)
    }

    private func ended(status: Int32, generation gen: Int) {
        lock.lock()
        guard gen == generation else { lock.unlock(); return }
        // `--resume` refused (session gone, other folder): start fresh next time.
        if spawnResumed && !initializedSinceSpawn { currentSessionId = nil }
        process = nil
        stdin = nil
        let pending = turn
        turn = nil
        lock.unlock()
        pending?.continuation.resume(throwing: ClaudeCodeError.exited(status, logTail()))
    }
}
#endif
