#if !APPSTORE
import Foundation

/// Finds the user's `claude` CLI and prepares the environment it runs in.
enum ClaudeCodeLocator {

    /// Where `claude` usually lives; an app launched from the Dock doesn't get
    /// the shell's PATH.
    /// The places looked in, in order. Separate from `executable` so a test can
    /// check the order without a `claude` on the machine running it.
    static func searchPaths(home: String = FileManager.default.homeDirectoryForCurrentUser.path) -> [String] {
        [
            "\(home)/.claude/local/claude",
            "\(home)/.local/bin/claude",
            "/opt/homebrew/bin/claude",
            "/usr/local/bin/claude",
            "\(home)/.npm-global/bin/claude",
            "\(home)/.bun/bin/claude",
        ]
    }

    /// `isExecutable` is injectable for the same reason.
    static func executable(
        home: String = FileManager.default.homeDirectoryForCurrentUser.path,
        isExecutable: (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }
    ) -> URL? {
        searchPaths(home: home).first(where: isExecutable).map { URL(fileURLWithPath: $0) }
    }

    /// The child's environment: the binary's folder and the usual tool folders
    /// on PATH (hooks and skills call python, node, git…), minus the markers
    /// that would make `claude` think it runs nested inside another session.
    static func environment(executable: URL,
                            base: [String: String] = ProcessInfo.processInfo.environment,
                            extra: [String: String]) -> [String: String] {
        var env = base
        let home = env["HOME"] ?? FileManager.default.homeDirectoryForCurrentUser.path
        env["PATH"] = [executable.deletingLastPathComponent().path, "/opt/homebrew/bin", "/usr/local/bin",
                       "/usr/bin", "/bin", "/usr/sbin", "/sbin", "\(home)/.local/bin", base["PATH"] ?? ""]
            .filter { !$0.isEmpty }
            .joined(separator: ":")
        for marker in ["CLAUDECODE", "CLAUDE_CODE_ENTRYPOINT", "CLAUDE_CODE_SSE_PORT"] {
            env.removeValue(forKey: marker)
        }
        // The point of this provider is that it runs on the user's Claude login.
        // A key exported in their shell would be inherited here and quietly billed
        // to the API instead, so it never reaches the child.
        for key in ["ANTHROPIC_API_KEY", "ANTHROPIC_AUTH_TOKEN"] {
            env.removeValue(forKey: key)
        }
        env.merge(extra) { _, new in new }
        return env
    }

    struct AuthStatus: Decodable, Equatable, Sendable {
        let loggedIn: Bool
        let authMethod: String?
        let email: String?
        let subscriptionType: String?
        let orgName: String?
    }

    /// `claude auth status` (JSON). nil when the command fails or times out.
    static func authStatus(executable: URL, timeout: TimeInterval = 10) async -> AuthStatus? {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = executable
            process.arguments = ["auth", "status"]
            process.environment = environment(executable: executable, extra: [:])
            let output = Pipe()
            process.standardOutput = output
            process.standardError = FileHandle.nullDevice
            process.standardInput = FileHandle.nullDevice
            let once = ResumeOnce(continuation)
            process.terminationHandler = { _ in
                let data = output.fileHandleForReading.readDataToEndOfFile()
                once.resume(try? JSONDecoder().decode(AuthStatus.self, from: data))
            }
            do { try process.run() } catch { once.resume(nil); return }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                if process.isRunning { process.terminate() }
                once.resume(nil)
            }
        }
    }
}

/// Resumes a continuation exactly once, whichever callback gets there first.
private final class ResumeOnce<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<T, Never>?
    init(_ continuation: CheckedContinuation<T, Never>) { self.continuation = continuation }
    func resume(_ value: T) {
        let pending = lock.withLock { () -> CheckedContinuation<T, Never>? in
            defer { continuation = nil }
            return continuation
        }
        pending?.resume(returning: value)
    }
}
#endif
