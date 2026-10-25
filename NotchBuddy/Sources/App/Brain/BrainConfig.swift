#if !APPSTORE
import Foundation

enum BrainConfigError: LocalizedError, Equatable {
    case unreadable
    case tooLarge
    case invalid(String)

    var errorDescription: String? {
        switch self {
        case .unreadable: "\(BrainConfig.fileName) can't be read."
        case .tooLarge: "\(BrainConfig.fileName) is too large."
        case .invalid(let reason): "\(BrainConfig.fileName) is not valid: \(reason)."
        }
    }
}

/// A brain's own conventions, from `<brain folder>/.coucou/brain.json`: where a
/// dropped file goes, which queues the Brain card counts and what their buttons do,
/// the local services it watches, extra instructions for Mochi. Every key is
/// optional; no file, or a broken one, means the generic defaults. Foundation only
/// (no AppKit, no app state, no logging), so the tests can use it.
struct BrainConfig: Equatable, Sendable {
    static let fileName = ".coucou/brain.json"
    /// The card is ~200 pt wide: more rows or buttons than this are ignored.
    static let maxCounters = 3
    static let maxServices = 2
    /// A config is a few lines; anything bigger is not one.
    static let maxFileBytes = 256 * 1024

    static let defaultInboxFolder = "Inbox"
    static let defaultAttachmentsSubfolder = "attachments"
    static let defaultIgnore: Set<String> = ["README.md"]
    static let defaultNoteHeader = "- Captured: {date}\n- Source: Coucou — {source}"
    static let defaultPattern = "*.md"

    static let `default` = BrainConfig()

    /// Where "Save to brain" puts a dropped file, and how the note starts.
    struct Inbox: Equatable, Sendable {
        /// Folders inside the vault, as "a/b" (no `.`, `..`, `~` or leading `/`).
        let folder: String
        let attachments: String
        /// Names in the inbox folder that are not notes (a README, a template).
        let ignore: Set<String>
        /// Lines under the note's title, with `{date}`, `{source}` and `{title}`
        /// filled in; empty for none.
        let noteHeader: String

        /// A folder that is empty or would leave the vault keeps its default; the
        /// attachments default to a subfolder of the inbox.
        init(folder: String? = nil, attachments: String? = nil, ignore: [String]? = nil, noteHeader: String? = nil) {
            let folder = folder.flatMap(BrainConfig.vaultRelative) ?? BrainConfig.defaultInboxFolder
            self.folder = folder
            self.attachments = attachments.flatMap(BrainConfig.vaultRelative)
                ?? "\(folder)/\(BrainConfig.defaultAttachmentsSubfolder)"
            self.ignore = ignore.map(Set.init) ?? BrainConfig.defaultIgnore
            self.noteHeader = noteHeader ?? BrainConfig.defaultNoteHeader
        }
    }

    /// One queue on the card: a label, a count and an optional button.
    struct Counter: Equatable, Sendable {
        enum Kind: String, Sendable {
            /// Notes not processed yet: first line isn't `---`; `inbox.ignore` skipped.
            case notesWithoutFrontmatter
            /// Every file whose name matches the pattern.
            case files
        }
        let label: String
        let kind: Kind
        /// Folders whose top-level files add up: in the vault, `~/…` or absolute.
        let paths: [String]
        /// `*` and `?` wildcards on the file name.
        let pattern: String
        let action: Action?

        init(label: String, kind: Kind, paths: [String], pattern: String = BrainConfig.defaultPattern,
             action: Action? = nil) {
            self.label = label
            self.kind = kind
            self.paths = paths
            self.pattern = pattern
            self.action = action
        }
    }

    /// What a counter's button does in the brain chat.
    struct Action: Equatable, Sendable {
        enum Effect: Equatable, Sendable {
            /// Sent to the brain as a message.
            case send(String)
            /// Typed in the chat's field, for the user to finish.
            case draft(String)
        }
        let label: String
        let effect: Effect
    }

    /// A local service: a dot in the card's header and/or a button that opens it.
    struct Service: Equatable, Sendable {
        let name: String
        /// Probed on every read, 2xx = up. Loopback only, so a vault shared by
        /// someone else can't make the app call out.
        let health: URL?
        /// A web page, opened on click.
        let open: URL?
    }

    /// Extra instructions appended to Mochi's brain prompt.
    let prompt: String?
    let inbox: Inbox
    let counters: [Counter]
    let services: [Service]

    init(prompt: String? = nil, inbox: Inbox = Inbox(), counters: [Counter] = [], services: [Service] = []) {
        let prompt = prompt?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.prompt = prompt?.isEmpty == false ? prompt : nil
        self.inbox = inbox
        self.counters = Array(counters.prefix(Self.maxCounters))
        self.services = Array(services.prefix(Self.maxServices))
    }

    // MARK: - Loading

    /// The vault's config; the defaults when it has no file or a broken one.
    static func load(vault: URL) -> BrainConfig {
        (try? read(vault: vault).get()) ?? .default
    }

    /// The vault's config, or why its file can't be used. No file is not an error.
    static func read(vault: URL) -> Result<BrainConfig, BrainConfigError> {
        let url = vault.appendingPathComponent(fileName)
        guard FileManager.default.fileExists(atPath: url.path) else { return .success(.default) }
        guard let handle = try? FileHandle(forReadingFrom: url) else { return .failure(.unreadable) }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: maxFileBytes + 1) else { return .failure(.unreadable) }
        guard data.count <= maxFileBytes else { return .failure(.tooLarge) }
        return parse(data)
    }

    static func parse(_ data: Data) -> Result<BrainConfig, BrainConfigError> {
        do {
            return .success(BrainConfig(try JSONDecoder().decode(File.self, from: data)))
        } catch let error as DecodingError {
            return .failure(.invalid(reason(error)))
        } catch {
            return .failure(.invalid(error.localizedDescription))
        }
    }

    /// The brain's extra instructions for the chat's system prompt; nil without a
    /// brain folder, a usable file or a `prompt`.
    static func promptAddition(vault: URL?) -> String? {
        vault.flatMap { load(vault: $0).prompt }
    }

    // MARK: - Paths

    /// A counter's folder: `~/…` under `home`, `/…` as is, anything else in the vault.
    static func resolve(_ path: String, vault: URL, home: URL) -> URL {
        if path == "~" { return home }
        if path.hasPrefix("~/") { return home.appendingPathComponent(String(path.dropFirst(2)), isDirectory: true) }
        if path.hasPrefix("/") { return URL(fileURLWithPath: path, isDirectory: true) }
        return vault.appendingPathComponent(path, isDirectory: true)
    }

    /// `path` as a folder inside the vault ("Inbox/attachments"); nil when it is
    /// empty or could point outside it (`~`, a leading `/`, `..`).
    static func vaultRelative(_ path: String) -> String? {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.hasPrefix("/"), !trimmed.hasPrefix("~") else { return nil }
        let parts = trimmed.split(separator: "/").filter { $0 != "." }
        guard !parts.isEmpty, !parts.contains("..") else { return nil }
        return parts.joined(separator: "/")
    }

    private static let loopbackHosts: Set<String> = ["localhost", "127.0.0.1", "::1"]

    /// An http(s) URL on this Mac; nil for anything else.
    static func loopbackURL(_ string: String?) -> URL? {
        guard let url = safeWebURL(string), let host = url.host?.lowercased(),
              loopbackHosts.contains(host) else { return nil }
        return url
    }

    // MARK: - File

    /// The file as written: every key optional, unknown keys ignored.
    fileprivate struct File: Codable {
        struct Inbox: Codable {
            let folder: String?
            let attachments: String?
            let ignore: [String]?
            let noteHeader: String?
        }
        struct Action: Codable {
            let label: String?
            let send: String?
            let draft: String?
        }
        struct Counter: Codable {
            let label: String?
            let kind: String?
            let paths: [String]?
            let pattern: String?
            let action: Action?
        }
        struct Service: Codable {
            let name: String?
            let health: String?
            let open: String?
        }
        let prompt: String?
        let inbox: Inbox?
        let counters: [Counter]?
        let services: [Service]?
    }

    /// Entries that can't be shown are dropped, not the whole file.
    fileprivate init(_ file: File) {
        self.init(
            prompt: file.prompt,
            inbox: Inbox(folder: file.inbox?.folder, attachments: file.inbox?.attachments,
                         ignore: file.inbox?.ignore, noteHeader: file.inbox?.noteHeader),
            counters: (file.counters ?? []).compactMap(Counter.init),
            services: (file.services ?? []).compactMap(Service.init))
    }

    /// "counters[1].paths: expected an array", short enough for one log line.
    private static func reason(_ error: DecodingError) -> String {
        func path(_ context: DecodingError.Context) -> String {
            context.codingPath.reduce("") { result, key in
                if let index = key.intValue { return "\(result)[\(index)]" }
                return result.isEmpty ? key.stringValue : "\(result).\(key.stringValue)"
            }
        }
        func noun(_ type: Any.Type) -> String {
            let name = String(describing: type)
            if name.hasPrefix("Array") { return "a list" }
            if name.hasPrefix("Dictionary") { return "an object" }
            return type == String.self ? "a string" : name
        }
        switch error {
        case .typeMismatch(let type, let context), .valueNotFound(let type, let context):
            let at = path(context)
            return "\(at.isEmpty ? "the file" : at) should be \(noun(type))"
        case .dataCorrupted(let context) where context.codingPath.isEmpty:
            return "not JSON"
        case .dataCorrupted(let context):
            return "\(path(context)) is malformed"
        case .keyNotFound(let key, _):
            return "\(key.stringValue) is missing"
        @unknown default:
            return "unreadable JSON"
        }
    }
}

private extension BrainConfig.Counter {
    /// Needs a label and a folder; an unknown kind drops the counter, a missing
    /// one counts files.
    init?(_ raw: BrainConfig.File.Counter) {
        guard let label = raw.label?.trimmingCharacters(in: .whitespacesAndNewlines), !label.isEmpty
        else { return nil }
        let kind: Kind
        if let name = raw.kind?.trimmingCharacters(in: .whitespacesAndNewlines) {
            guard let known = Kind(rawValue: name) else { return nil }
            kind = known
        } else {
            kind = .files
        }
        let paths = (raw.paths ?? []).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard !paths.isEmpty else { return nil }
        let pattern = raw.pattern?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        self.init(label: label, kind: kind, paths: paths,
                  pattern: pattern.isEmpty ? BrainConfig.defaultPattern : pattern,
                  action: raw.action.flatMap(BrainConfig.Action.init))
    }
}

private extension BrainConfig.Action {
    /// Exactly one of `send` and `draft`; the label defaults to the text itself.
    init?(_ raw: BrainConfig.File.Action) {
        let send = raw.send?.trimmingCharacters(in: .whitespacesAndNewlines)
        let draft = raw.draft
        let hasSend = send?.isEmpty == false
        let hasDraft = draft?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        let effect: Effect
        switch (hasSend, hasDraft) {
        case (true, false): effect = .send(send ?? "")
        case (false, true): effect = .draft(draft ?? "")
        default: return nil
        }
        let label = raw.label?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let text = (send ?? draft ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        self.init(label: label.isEmpty ? text : label, effect: effect)
    }
}

private extension BrainConfig.Service {
    /// Needs a name and something to show: a usable `health` or `open` URL.
    init?(_ raw: BrainConfig.File.Service) {
        guard let name = raw.name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty
        else { return nil }
        let health = BrainConfig.loopbackURL(raw.health)
        let open = safeWebURL(raw.open)
        guard health != nil || open != nil else { return nil }
        self.init(name: name, health: health, open: open)
    }
}
#endif
