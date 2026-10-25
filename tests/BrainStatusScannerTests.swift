import Foundation

/// The Brain card's counters, from the default config and a custom one, on fake
/// vaults; the file-name patterns; the brain folder helpers. Run with
/// scripts/test-brain-status.sh (argument: an empty scratch folder).
@main
enum BrainStatusScannerTests {
    static func main() throws {
        var cases = 0
        func check(_ name: String, _ condition: Bool, _ detail: @autoclosure () -> String = "") {
            precondition(condition, "\(name) failed \(detail())")
            cases += 1
        }

        let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let fm = FileManager.default
        func write(_ url: URL, _ text: String) throws {
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(text.utf8).write(to: url)
        }
        func folder(_ url: URL) throws { try fm.createDirectory(at: url, withIntermediateDirectories: true) }

        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let home = root.appendingPathComponent("home", isDirectory: true)
        try folder(home)

        let process = BrainConfig.Action(label: "Process", effect: .send("/process"))
        let review = BrainConfig.Action(label: "Review", effect: .draft("/review "))
        let notes = BrainConfig.Counter(label: "Inbox", kind: .notesWithoutFrontmatter, paths: ["Inbox"], action: process)
        let drafts = BrainConfig.Counter(label: "Drafts", kind: .files, paths: ["Drafts", "~/queue"], action: review)
        let images = BrainConfig.Counter(label: "Images", kind: .files, paths: ["Inbox/attachments"], pattern: "*.png")
        let search = BrainConfig.Service(name: "Search", health: URL(string: "http://localhost:1234/health"),
                                         open: URL(string: "http://localhost:1234"))
        let custom = BrainConfig(
            inbox: BrainConfig.Inbox(ignore: ["README.md", "template.md"]),
            counters: [notes, drafts, images],
            services: [search])
        func value(_ counter: BrainConfig.Counter, _ vault: URL, ignore: Set<String> = custom.inbox.ignore) -> Int? {
            BrainStatusScanner.count(counter, vault: vault, home: home, ignore: ignore)
        }

        // MARK: No brain folder

        let unset = BrainStatusScanner.scan(vault: nil, config: custom, home: home, now: now)
        check("no vault: not configured", !unset.vaultConfigured)
        check("no vault: no counters or services", unset.counters.isEmpty && unset.services.isEmpty, "\(unset)")
        check("no vault: stamped", unset.lastUpdated == now)

        // MARK: Default config

        let empty = root.appendingPathComponent("empty", isDirectory: true)
        try folder(empty)
        let bare = BrainStatusScanner.scan(vault: empty, config: .default, home: home, now: now)
        check("default config: configured, nothing to show",
              bare == BrainStatus(vaultConfigured: true, counters: [], services: [], lastUpdated: now), "\(bare)")

        // MARK: Missing folders

        let missing = BrainStatusScanner.scan(vault: empty, config: custom, home: home, now: now)
        check("one row per counter", missing.counters.map(\.label) == ["Inbox", "Drafts", "Images"])
        check("missing folders read as unknown", missing.counters.allSatisfy { $0.value == nil }, "\(missing.counters)")
        check("actions carried even when unknown", missing.counters.map(\.action) == [process, review, nil])
        check("services not probed by the scan",
              missing.services == [BrainStatus.Service(name: "Search", health: search.health, open: search.open, up: nil)])

        // MARK: Notes without frontmatter

        let vault = root.appendingPathComponent("vault", isDirectory: true)
        let inbox = vault.appendingPathComponent("Inbox")
        try folder(inbox)
        check("empty inbox is zero", value(notes, vault) == 0)

        try write(inbox.appendingPathComponent("a.md"), "# Idea\ntext")                    // pending
        try write(inbox.appendingPathComponent("b.md"), "---\ndate: 2026-10-15\n---\n# Done") // processed
        try write(inbox.appendingPathComponent("template.md"), "# {{title}}")              // ignored by the config
        try write(inbox.appendingPathComponent("README.md"), "# Inbox")                    // ignored by the config
        try write(inbox.appendingPathComponent(".hidden.md"), "# hidden")                  // hidden
        try write(inbox.appendingPathComponent("c.txt"), "not markdown")                   // not .md
        try write(inbox.appendingPathComponent("board.canvas"), "{}")                      // not .md
        try write(inbox.appendingPathComponent("meetings/d.md"), "# subfolder")           // not top level
        try write(inbox.appendingPathComponent("e.md"), "")                                // empty: pending
        try write(inbox.appendingPathComponent("f.md"), "\u{FEFF}---\r\ndate: x\r\n---\r\n") // BOM + CRLF: processed
        try write(inbox.appendingPathComponent("g.md"), "---  \ntags: []\n---\n")           // trailing spaces: processed
        try write(inbox.appendingPathComponent("h.md"), "----\nnot frontmatter")            // pending
        try write(inbox.appendingPathComponent("i.md"), "\n---\nlate")                      // first line empty: pending
        try folder(inbox.appendingPathComponent("folder.md"))                              // a folder named .md
        check("counts only unprocessed top-level notes", value(notes, vault) == 4, String(describing: value(notes, vault)))
        check("ignore list comes from the config", value(notes, vault, ignore: []) == 6,
              String(describing: value(notes, vault, ignore: [])))
        check("default ignore skips README.md only", value(notes, vault, ignore: BrainConfig.default.inbox.ignore) == 5,
              String(describing: value(notes, vault, ignore: BrainConfig.default.inbox.ignore)))
        let txtNotes = BrainConfig.Counter(label: "Text", kind: .notesWithoutFrontmatter, paths: ["Inbox"], pattern: "*.txt")
        check("a pattern narrows the notes", value(txtNotes, vault) == 1)

        check("frontmatter: plain", BrainStatusScanner.hasFrontmatter(inbox.appendingPathComponent("b.md")))
        check("frontmatter: BOM and CRLF", BrainStatusScanner.hasFrontmatter(inbox.appendingPathComponent("f.md")))
        check("frontmatter: trailing spaces", BrainStatusScanner.hasFrontmatter(inbox.appendingPathComponent("g.md")))
        check("no frontmatter: four dashes", !BrainStatusScanner.hasFrontmatter(inbox.appendingPathComponent("h.md")))
        check("no frontmatter: empty file", !BrainStatusScanner.hasFrontmatter(inbox.appendingPathComponent("e.md")))
        check("no frontmatter: missing file", !BrainStatusScanner.hasFrontmatter(inbox.appendingPathComponent("nope.md")))

        // MARK: Files

        let draftsFolder = vault.appendingPathComponent("Drafts")
        try write(draftsFolder.appendingPathComponent("2026-10-14_one.md"), "---\nprocessed: true\n---\n")  // counted anyway
        try write(draftsFolder.appendingPathComponent("two.md"), "x")
        try write(draftsFolder.appendingPathComponent("index.json"), "{}")                                  // not *.md
        try write(draftsFolder.appendingPathComponent("three.md.bak"), "x")                                 // not *.md
        try write(draftsFolder.appendingPathComponent(".lock.md"), "")                                      // hidden
        try write(draftsFolder.appendingPathComponent("old/four.md"), "x")                                  // not top level
        check("vault folder alone (the home one is missing)", value(drafts, vault) == 2, String(describing: value(drafts, vault)))

        let queue = home.appendingPathComponent("queue")
        for n in 1...3 { try write(queue.appendingPathComponent("q\(n).md"), "dump") }
        try write(queue.appendingPathComponent(".q4.md"), "")
        check("folders add up", value(drafts, vault) == 5, String(describing: value(drafts, vault)))
        check("home folder alone", value(drafts, empty) == 3, String(describing: value(drafts, empty)))

        let attachments = inbox.appendingPathComponent("attachments")
        try write(attachments.appendingPathComponent("photo.png"), "png")
        try write(attachments.appendingPathComponent("scan.PNG"), "png")     // patterns are case-sensitive
        try write(attachments.appendingPathComponent("report.pdf"), "pdf")
        check("pattern picks the files", value(images, vault) == 1, String(describing: value(images, vault)))
        check("attachments folder isn't an inbox note", value(notes, vault) == 4)

        let full = BrainStatusScanner.scan(vault: vault, config: custom, home: home, now: now)
        check("full scan", full == BrainStatus(
            vaultConfigured: true,
            counters: [
                BrainStatus.Counter(label: "Inbox", kind: .notesWithoutFrontmatter, value: 4, action: process),
                BrainStatus.Counter(label: "Drafts", kind: .files, value: 5, action: review),
                BrainStatus.Counter(label: "Images", kind: .files, value: 1, action: nil),
            ],
            services: [BrainStatus.Service(name: "Search", health: search.health, open: search.open, up: nil)],
            lastUpdated: now), "\(full)")

        // MARK: Patterns

        func expectMatch(_ name: String, _ pattern: String, _ expected: Bool) {
            check("\(String(reflecting: name)) ~ \(String(reflecting: pattern))",
                  BrainStatusScanner.matches(name, pattern: pattern) == expected)
        }
        expectMatch("note.md", "*.md", true)
        expectMatch(".md", "*.md", true)
        expectMatch("note.md.bak", "*.md", false)
        expectMatch("note.MD", "*.md", false)
        expectMatch("anything", "*", true)
        expectMatch("", "*", true)
        expectMatch("", "?", false)
        expectMatch("log-07.txt", "log-??.txt", true)
        expectMatch("log-7.txt", "log-??.txt", false)
        expectMatch("a-b-c-d", "a*c*d", true)
        expectMatch("a-b-c", "a*c*d", false)
        expectMatch("aaab", "*a*b", true)
        expectMatch("résumé.md", "r?sum?.md", true)
        expectMatch("[x].md", "[x].md", true)
        expectMatch("x.md", "[x].md", false)
        expectMatch("plain", "plain", true)
        expectMatch("plain", "**", true)

        // MARK: Brain folder

        check("unset path", BrainVault.url(path: "") == nil && BrainVault.url(path: "   ") == nil)
        check("missing path", BrainVault.url(path: root.appendingPathComponent("nope").path) == nil)
        check("a file is not a vault", BrainVault.url(path: inbox.appendingPathComponent("a.md").path) == nil)
        check("a folder is", BrainVault.url(path: vault.path)?.standardizedFileURL.path == vault.standardizedFileURL.path)
        check("surrounding spaces ignored", BrainVault.url(path: " \(vault.path) \n") != nil)
        check("tilde expanded",
              BrainVault.url(path: "~")?.standardizedFileURL.path == fm.homeDirectoryForCurrentUser.standardizedFileURL.path)

        let odd = URL(fileURLWithPath: "/Volumes/Data/My Vault/Ñandú & co #1", isDirectory: true)
        let link = BrainVault.obsidianURL(for: odd)?.absoluteString ?? ""
        let prefix = "obsidian://open?path="
        check("obsidian link scheme", link.hasPrefix(prefix + "/Volumes/Data/My%20Vault/"), link)
        check("obsidian link encodes & and #", link.contains("%20%26%20co%20%231"), link)
        check("obsidian link has nothing raw", !link.dropFirst(prefix.count).contains { " &#?é".contains($0) }, link)
        check("obsidian link round-trips", String(link.dropFirst(prefix.count)).removingPercentEncoding == odd.path, link)

        print("Brain status: \(cases) cases passed")
    }
}
