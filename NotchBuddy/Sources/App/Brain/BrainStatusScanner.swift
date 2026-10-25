#if !APPSTORE
import Foundation

/// What the Brain card shows: the queues and services of the brain's config.
struct BrainStatus: Equatable, Sendable {
    struct Counter: Equatable, Sendable {
        let label: String
        let kind: BrainConfig.Counter.Kind
        /// nil when none of the counter's folders exists.
        let value: Int?
        let action: BrainConfig.Action?
    }

    struct Service: Equatable, Sendable {
        let name: String
        let health: URL?
        let open: URL?
        /// nil until probed, or when the service has no health URL.
        var up: Bool?
    }

    /// The brain folder is set in Settings and exists.
    var vaultConfigured = false
    var counters: [Counter] = []
    var services: [Service] = []
    var lastUpdated: Date?
}

/// Counts the queues a brain's config declares: top-level files only, hidden files
/// skipped. Foundation only (no AppKit, no app state), so the tests can run it on
/// a fake vault.
enum BrainStatusScanner {
    /// Enough to hold a first line of `---` after a BOM and some spaces.
    private static let headerBytes = 64

    /// The counts for `vault` (nil = no brain folder set); the probes stay nil.
    static func scan(vault: URL?, config: BrainConfig, home: URL, now: Date = Date()) -> BrainStatus {
        guard let vault else { return BrainStatus(lastUpdated: now) }
        return BrainStatus(
            vaultConfigured: true,
            counters: config.counters.map { counter in
                BrainStatus.Counter(label: counter.label, kind: counter.kind,
                                    value: count(counter, vault: vault, home: home, ignore: config.inbox.ignore),
                                    action: counter.action)
            },
            services: config.services.map { BrainStatus.Service(name: $0.name, health: $0.health, open: $0.open) },
            lastUpdated: now)
    }

    /// The counter's matching files over all its folders; nil when none exists.
    static func count(_ counter: BrainConfig.Counter, vault: URL, home: URL, ignore: Set<String>) -> Int? {
        let folders = counter.paths.compactMap { files(in: BrainConfig.resolve($0, vault: vault, home: home)) }
        guard !folders.isEmpty else { return nil }
        return folders.reduce(0) { total, files in
            total + files.filter { file in
                guard matches(file.lastPathComponent, pattern: counter.pattern) else { return false }
                switch counter.kind {
                case .files: return true
                case .notesWithoutFrontmatter:
                    return !ignore.contains(file.lastPathComponent) && !hasFrontmatter(file)
                }
            }.count
        }
    }

    /// True when the first line is `---` (a BOM, trailing spaces or CRLF allowed).
    /// An empty or unreadable file has none, like `head -n1` sees it.
    static func hasFrontmatter(_ file: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: file) else { return false }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: headerBytes), !data.isEmpty else { return false }
        var text = String(decoding: data, as: UTF8.self)
        if text.hasPrefix("\u{FEFF}") { text.removeFirst() }
        // "\r\n" is one Character, so split on any newline rather than on "\n".
        let firstLine = text.split(maxSplits: 1, omittingEmptySubsequences: false, whereSeparator: \.isNewline).first ?? ""
        return firstLine.trimmingCharacters(in: .whitespaces) == "---"
    }

    /// `name` matches `pattern`, where `*` is any run of characters and `?` any one.
    static func matches(_ name: String, pattern: String) -> Bool {
        let name = Array(name), pattern = Array(pattern)
        var n = 0, p = 0
        // The last `*` seen and where in `name` it started matching, to backtrack to.
        var star: Int?
        var starMatch = 0
        while n < name.count {
            if p < pattern.count, pattern[p] == "?" || pattern[p] == name[n] {
                n += 1
                p += 1
            } else if p < pattern.count, pattern[p] == "*" {
                star = p
                starMatch = n
                p += 1
            } else if let star {
                starMatch += 1
                n = starMatch
                p = star + 1
            } else {
                return false
            }
        }
        while p < pattern.count, pattern[p] == "*" { p += 1 }
        return p == pattern.count
    }

    /// Visible top-level regular files of `folder`; nil when it isn't a folder.
    private static func files(in folder: URL) -> [URL]? {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDirectory),
              isDirectory.boolValue,
              let entries = try? FileManager.default.contentsOfDirectory(
                at: folder, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles])
        else { return nil }
        return entries.filter { (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true }
    }
}
#endif
