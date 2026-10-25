import Foundation

/// `.coucou/brain.json`: defaults, every key, partial and broken files, paths,
/// actions and services. Run with scripts/test-brain-config.sh (arguments: an
/// empty scratch folder for fake vaults, then docs/brain.example.json).
@main
enum BrainConfigTests {
    static func main() throws {
        var cases = 0
        func check(_ name: String, _ condition: Bool, _ detail: @autoclosure () -> String = "") {
            precondition(condition, "\(name) failed \(detail())")
            cases += 1
        }
        func parse(_ json: String) -> Result<BrainConfig, BrainConfigError> { BrainConfig.parse(Data(json.utf8)) }
        func config(_ json: String) -> BrainConfig {
            switch parse(json) {
            case .success(let config): return config
            case .failure(let error): preconditionFailure("\(json) should parse: \(error)")
            }
        }
        func failure(_ json: String) -> BrainConfigError? {
            if case .failure(let error) = parse(json) { return error }
            return nil
        }

        let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let example = URL(fileURLWithPath: CommandLine.arguments[2])
        let fm = FileManager.default
        var vaultCount = 0
        func makeVault(config json: String? = nil) throws -> URL {
            vaultCount += 1
            let vault = root.appendingPathComponent("vault-\(vaultCount)", isDirectory: true)
            try fm.createDirectory(at: vault, withIntermediateDirectories: true)
            if let json {
                let file = vault.appendingPathComponent(BrainConfig.fileName)
                try fm.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
                try Data(json.utf8).write(to: file)
            }
            return vault
        }

        // MARK: Defaults

        let defaults = BrainConfig.default
        check("default inbox folder", defaults.inbox.folder == "Inbox", defaults.inbox.folder)
        check("default attachments", defaults.inbox.attachments == "Inbox/attachments", defaults.inbox.attachments)
        check("default ignore", defaults.inbox.ignore == ["README.md"])
        check("default header", defaults.inbox.noteHeader == "- Captured: {date}\n- Source: Coucou — {source}")
        check("default has no counters, services or prompt",
              defaults.counters.isEmpty && defaults.services.isEmpty && defaults.prompt == nil)
        check("empty object is the default", config("{}") == defaults)
        check("unknown keys are ignored", config(#"{"theme": "dark", "inbox": {"colour": 1}}"#) == defaults)

        // MARK: Every key

        let full = config(try String(contentsOf: example, encoding: .utf8))
        check("example: prompt", full.prompt == "Extra instructions appended to Mochi's brain prompt.")
        check("example: inbox", full.inbox == BrainConfig.Inbox(
            folder: "Inbox", attachments: "Inbox/attachments", ignore: ["README.md"],
            noteHeader: "- Captured: {date}\n- Source: Coucou — {source}"), "\(full.inbox)")
        check("example: two counters", full.counters.count == 2, "\(full.counters)")
        check("example: notes counter", full.counters.first == BrainConfig.Counter(
            label: "Inbox", kind: .notesWithoutFrontmatter, paths: ["Inbox"], pattern: "*.md",
            action: BrainConfig.Action(label: "Process", effect: .send("/process-inbox"))), "\(full.counters)")
        check("example: files counter", full.counters.last == BrainConfig.Counter(
            label: "Drafts", kind: .files, paths: ["Drafts", "~/Notes/queue"], pattern: "*.md",
            action: BrainConfig.Action(label: "Review", effect: .draft("/review "))), "\(full.counters)")
        check("example: service", full.services == [BrainConfig.Service(
            name: "Search", health: URL(string: "http://localhost:1234/health"),
            open: URL(string: "http://localhost:1234"))], "\(full.services)")

        let custom = config(#"""
        {
          "prompt": "  Answer in haiku.\n",
          "inbox": {"folder": "Notes/New", "attachments": "Files", "ignore": ["TEMPLATE.md", "index.md"],
                    "noteHeader": "From {source}"},
          "counters": [{"label": "Logs", "kind": "files", "paths": ["/var/log"], "pattern": "*.log"}]
        }
        """#)
        check("prompt trimmed", custom.prompt == "Answer in haiku.", String(describing: custom.prompt))
        check("custom inbox", custom.inbox.folder == "Notes/New" && custom.inbox.attachments == "Files"
              && custom.inbox.ignore == ["TEMPLATE.md", "index.md"] && custom.inbox.noteHeader == "From {source}",
              "\(custom.inbox)")
        check("counter without action", custom.counters.first?.action == nil && custom.counters.first?.pattern == "*.log")

        // MARK: Partial files

        let folderOnly = config(#"{"inbox": {"folder": "Captures"}}"#)
        check("attachments follow the inbox folder", folderOnly.inbox.attachments == "Captures/attachments",
              folderOnly.inbox.attachments)
        check("other inbox keys keep their defaults",
              folderOnly.inbox.ignore == defaults.inbox.ignore && folderOnly.inbox.noteHeader == defaults.inbox.noteHeader)
        check("only a prompt", config(#"{"prompt": "Be brief."}"#).prompt == "Be brief.")
        check("blank prompt is none", config(#"{"prompt": " \n "}"#).prompt == nil)
        check("empty header is kept empty", config(#"{"inbox": {"noteHeader": ""}}"#).inbox.noteHeader == "")
        check("empty ignore list ignores nothing", config(#"{"inbox": {"ignore": []}}"#).inbox.ignore.isEmpty)
        check("null values are defaults", config(#"{"prompt": null, "inbox": null, "counters": null}"#) == defaults)

        // MARK: Inbox folders stay in the vault

        for escaping in ["../outside", "a/../../b", "/tmp/inbox", "~/inbox", "~", "", "  ", "."] {
            let parsed = config(#"{"inbox": {"folder": "\#(escaping)", "attachments": "\#(escaping)"}}"#)
            check("folder \(String(reflecting: escaping)) keeps the default",
                  parsed.inbox.folder == "Inbox" && parsed.inbox.attachments == "Inbox/attachments", "\(parsed.inbox)")
        }
        check("folder normalised", BrainConfig.vaultRelative(" ./Notes//./Captures/ ") == "Notes/Captures",
              String(describing: BrainConfig.vaultRelative(" ./Notes//./Captures/ ")))
        check("dots inside a name are fine", BrainConfig.vaultRelative("my..notes") == "my..notes")

        // MARK: Broken files

        check("not JSON", failure("{ inbox: ") == .invalid("not JSON"), "\(String(describing: failure("{ inbox: ")))")
        check("empty file", failure("") == .invalid("not JSON"))
        check("an array is not a config", failure("[]") == .invalid("the file should be an object"),
              "\(String(describing: failure("[]")))")
        check("wrong type is named", failure(#"{"counters": "Inbox"}"#) == .invalid("counters should be a list"),
              "\(String(describing: failure(#"{"counters": "Inbox"}"#)))")
        let nested = failure(#"{"counters": [{"label": "A", "paths": "Inbox"}]}"#)
        check("nested wrong type is located", nested == .invalid("counters[0].paths should be a list"),
              "\(String(describing: nested))")
        check("a number for a string", failure(#"{"prompt": 3}"#) == .invalid("prompt should be a string"),
              "\(String(describing: failure(#"{"prompt": 3}"#)))")
        check("errors read as sentences", BrainConfigError.invalid("not JSON").errorDescription?.contains("brain.json") == true)

        // MARK: Loading from the vault

        let noFile = try makeVault()
        check("no file: defaults, no error", (try? BrainConfig.read(vault: noFile).get()) == defaults)
        check("no file: load gives defaults", BrainConfig.load(vault: noFile) == defaults)

        let good = try makeVault(config: #"{"inbox": {"folder": "Captures"}}"#)
        check("file read from .coucou", BrainConfig.load(vault: good).inbox.folder == "Captures")

        let broken = try makeVault(config: #"{"inbox": {"folder": "Captures""#)
        if case .failure(let error) = BrainConfig.read(vault: broken) {
            check("broken file reports invalid", error == .invalid("not JSON"), "\(error)")
        } else {
            check("broken file reports an error", false)
        }
        check("broken file loads the defaults", BrainConfig.load(vault: broken) == defaults)

        let huge = try makeVault(config: "{\"prompt\": \"" + String(repeating: "x", count: BrainConfig.maxFileBytes) + "\"}")
        if case .failure(let error) = BrainConfig.read(vault: huge) {
            check("huge file is refused", error == .tooLarge, "\(error)")
        } else {
            check("huge file reports an error", false)
        }

        let folderInstead = try makeVault()
        try fm.createDirectory(at: folderInstead.appendingPathComponent(BrainConfig.fileName), withIntermediateDirectories: true)
        if case .failure(let error) = BrainConfig.read(vault: folderInstead) {
            check("a folder named brain.json is unreadable", error == .unreadable, "\(error)")
        } else {
            check("a folder named brain.json reports an error", false)
        }
        check("unreadable loads the defaults", BrainConfig.load(vault: folderInstead) == defaults)

        // MARK: Paths

        let vault = URL(fileURLWithPath: "/vaults/mine", isDirectory: true)
        let home = URL(fileURLWithPath: "/homes/someone", isDirectory: true)
        func resolved(_ path: String) -> String { BrainConfig.resolve(path, vault: vault, home: home).standardizedFileURL.path }
        check("relative is in the vault", resolved("Drafts") == "/vaults/mine/Drafts", resolved("Drafts"))
        check("nested relative", resolved("Notes/queue") == "/vaults/mine/Notes/queue", resolved("Notes/queue"))
        check("~/ is the home folder", resolved("~/Notes/queue") == "/homes/someone/Notes/queue", resolved("~/Notes/queue"))
        check("~ alone is the home folder", resolved("~") == "/homes/someone", resolved("~"))
        check("absolute stays absolute", resolved("/srv/queue") == "/srv/queue", resolved("/srv/queue"))
        check("~name is a vault folder", resolved("~drafts") == "/vaults/mine/~drafts", resolved("~drafts"))

        // MARK: Actions

        func action(_ json: String) -> BrainConfig.Action? {
            config(#"{"counters": [{"label": "Q", "paths": ["Q"], "action": \#(json)}]}"#).counters.first?.action
        }
        check("send", action(#"{"label": "Go", "send": " /go \n"}"#) == BrainConfig.Action(label: "Go", effect: .send("/go")))
        check("draft keeps its trailing space",
              action(#"{"label": "Ask", "draft": "/ask "}"#) == BrainConfig.Action(label: "Ask", effect: .draft("/ask ")))
        check("both is no button", action(#"{"label": "X", "send": "/a", "draft": "/b "}"#) == nil)
        check("neither is no button", action(#"{"label": "X"}"#) == nil)
        check("unknown verb is no button", action(#"{"label": "X", "run": "/a"}"#) == nil)
        check("blank send is ignored", action(#"{"label": "X", "send": "  ", "draft": "/b "}"#)?.effect == .draft("/b "))
        check("blank draft is ignored", action(#"{"label": "X", "send": "/a", "draft": " "}"#)?.effect == .send("/a"))
        check("label defaults to the text", action(#"{"draft": "/ask "}"#)?.label == "/ask")

        // MARK: Counters

        let counters = config(#"""
        {"counters": [
          {"label": "No kind", "paths": ["A"]},
          {"label": "Bad kind", "kind": "folders", "paths": ["A"]},
          {"kind": "files", "paths": ["A"]},
          {"label": "  ", "paths": ["A"]},
          {"label": "No paths", "kind": "files"},
          {"label": "Blank paths", "paths": ["", " "]},
          {"label": "Blank pattern", "kind": "notesWithoutFrontmatter", "paths": [" B "], "pattern": " "},
          {"label": "Third", "paths": ["C"]},
          {"label": "Fourth", "paths": ["D"]}
        ]}
        """#).counters
        check("invalid counters dropped, the rest capped at three",
              counters.map(\.label) == ["No kind", "Blank pattern", "Third"], "\(counters.map(\.label))")
        check("missing kind counts files", counters.first?.kind == .files)
        check("missing pattern is *.md", counters.first?.pattern == "*.md")
        check("blank pattern is *.md", counters.dropFirst().first?.pattern == "*.md")
        check("paths trimmed", counters.dropFirst().first?.paths == ["B"])

        // MARK: Services

        let services = config(#"""
        {"services": [
          {"name": "Remote", "health": "https://example.com/health"},
          {"health": "http://localhost:1/health"},
          {"name": "Local app", "open": "file:///Applications/Calculator.app"},
          {"name": "Six", "health": "http://[::1]:6/health", "open": "https://example.com/docs"},
          {"name": "Seven", "health": "http://127.0.0.1:7/"},
          {"name": "Eight", "open": "http://localhost:8"}
        ]}
        """#).services
        check("services without a usable URL or name dropped, capped at two",
              services.map(\.name) == ["Six", "Seven"], "\(services.map(\.name))")
        check("IPv6 loopback probed", services.first?.health == URL(string: "http://[::1]:6/health"))
        check("any web page can be opened", services.first?.open == URL(string: "https://example.com/docs"))
        check("health without open", services.last?.health != nil && services.last?.open == nil)
        let remote = config(#"{"services": [{"name": "Remote", "health": "https://example.com/h", "open": "https://example.com"}]}"#)
        check("remote health never probed, open kept",
              remote.services.first?.health == nil && remote.services.first?.open != nil, "\(remote.services)")
        check("LOCALHOST in capitals is loopback", BrainConfig.loopbackURL("http://LOCALHOST:3/h") != nil)
        check("a lookalike host is not", BrainConfig.loopbackURL("http://localhost.example.com/h") == nil)

        // MARK: Prompt addition

        check("no vault, no prompt", BrainConfig.promptAddition(vault: nil) == nil)
        check("no file, no prompt", BrainConfig.promptAddition(vault: noFile) == nil)
        let prompted = try makeVault(config: #"{"prompt": "\n Prefer the Notes folder. \n"}"#)
        check("prompt from the file", BrainConfig.promptAddition(vault: prompted) == "Prefer the Notes folder.",
              String(describing: BrainConfig.promptAddition(vault: prompted)))
        check("broken file, no prompt", BrainConfig.promptAddition(vault: broken) == nil)

        print("Brain config: \(cases) cases passed")
    }
}
