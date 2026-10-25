import Foundation

/// "Save to brain" with the default config and a custom one: slugs, unique names,
/// text vs attached capture, no frontmatter, header placeholders, empty header.
/// Run with scripts/test-brain-inbox.sh (argument: an empty scratch folder, used as
/// fake vaults — never a real one).
@main
enum BrainInboxTests {
    static func main() throws {
        var cases = 0
        func check(_ name: String, _ condition: Bool, _ detail: @autoclosure () -> String = "") {
            precondition(condition, "\(name) failed \(detail())")
            cases += 1
        }
        func expectSlug(_ stem: String, _ expected: String) {
            let actual = BrainInbox.slug(stem)
            check("slug \(String(reflecting: stem))", actual == expected, "→ \(String(reflecting: actual))")
        }

        let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let fm = FileManager.default
        let home = root.appendingPathComponent("home", isDirectory: true)
        let date = Calendar(identifier: .gregorian).date(from: DateComponents(year: 2026, month: 10, day: 15, hour: 12))!
        var vaultCount = 0
        func makeVault(inbox: String? = BrainConfig.default.inbox.folder) throws -> URL {
            vaultCount += 1
            let vault = root.appendingPathComponent("vault-\(vaultCount)", isDirectory: true)
            try fm.createDirectory(at: vault, withIntermediateDirectories: true)
            if let inbox {
                try fm.createDirectory(at: vault.appendingPathComponent(inbox), withIntermediateDirectories: true)
            }
            return vault
        }
        let sources = root.appendingPathComponent("sources", isDirectory: true)
        try fm.createDirectory(at: sources, withIntermediateDirectories: true)
        func source(_ name: String, _ data: Data) throws -> URL {
            let url = sources.appendingPathComponent(name)
            try data.write(to: url)
            return url
        }
        func read(_ url: URL) -> String { (try? String(contentsOf: url, encoding: .utf8)) ?? "<unreadable>" }
        func firstLine(_ url: URL) -> String { String(read(url).split(separator: "\n", omittingEmptySubsequences: false).first ?? "") }
        /// What the card would show for the inbox folder, counted the card's way.
        func pending(_ vault: URL, _ inbox: BrainConfig.Inbox = BrainConfig.default.inbox) -> Int? {
            let counter = BrainConfig.Counter(label: "Inbox", kind: .notesWithoutFrontmatter, paths: [inbox.folder])
            return BrainStatusScanner.count(counter, vault: vault, home: home, ignore: inbox.ignore)
        }

        // MARK: Slugs

        expectSlug("Résumé Q3 (final)", "resume-q3-final")
        expectSlug("  My   note__with  spaces ", "my-note-with-spaces")
        expectSlug("Ça va? Ñandú", "ca-va-nandu")
        expectSlug("Straße Æsir", "strasse-aesir")
        expectSlug("Привет мир", "privet-mir")
        expectSlug("!!! ???", BrainInbox.fallbackSlug)
        expectSlug("", BrainInbox.fallbackSlug)
        expectSlug("2026-10-04_ticket-it", "ticket-it")
        expectSlug("2026-10-04", "2026-10-04")
        expectSlug("v2.1-release_notes", "v2-1-release-notes")

        let long = BrainInbox.slug(String(repeating: "long word ", count: 12))
        check("long slug capped", long.count <= BrainInbox.maxSlugLength, "\(long.count) chars")
        check("long slug keeps its start", long.hasPrefix("long-word-long-word"), long)
        check("long slug has no trailing dash", !long.hasSuffix("-"), long)
        check("long slug is ascii kebab", long.allSatisfy { $0.isASCII && ($0.isLowercase || $0.isNumber || $0 == "-") }, long)

        // MARK: Names, title, date

        check("date stamp", BrainInbox.dateStamp(date) == "2026-10-15", BrainInbox.dateStamp(date))
        check("title turns underscores into spaces",
              BrainInbox.title(fromStem: "my_note  final", fallback: "x") == "my note final")
        check("title falls back on the file name", BrainInbox.title(fromStem: "  ", fallback: " .md") == " .md")
        check("attachment name drops what breaks an embed",
              BrainInbox.attachmentName("Report #1 [v2] a|b^c.pdf") == "Report -1 -v2- a-b-c.pdf",
              BrainInbox.attachmentName("Report #1 [v2] a|b^c.pdf"))
        check("attachment name is never hidden", BrainInbox.attachmentName(".env") == "env")

        // MARK: Header

        let values = ["date": "2026-10-15", "source": "a.txt", "title": "A"]
        check("placeholders filled", BrainInbox.fill("{title} from {source} on {date}", values) == "A from a.txt on 2026-10-15")
        check("unknown placeholders kept", BrainInbox.fill("{when} {date}", values) == "{when} 2026-10-15")
        check("unclosed brace kept", BrainInbox.fill("{date", values) == "{date")
        check("braces around a placeholder", BrainInbox.fill("{{date}}", values) == "{2026-10-15}")
        check("a value is never expanded again",
              BrainInbox.fill("{source} {date}", ["source": "{date}.md", "date": "today"]) == "{date}.md today")
        check("default header block",
              BrainInbox.noteHeader(title: "A", date: "2026-10-15", source: "a.txt", template: BrainConfig.defaultNoteHeader)
                == "# A\n\n- Captured: 2026-10-15\n- Source: Coucou — a.txt\n\n")
        check("empty header is the title alone",
              BrainInbox.noteHeader(title: "A", date: "d", source: "s", template: "") == "# A\n\n")
        check("blank header is the title alone",
              BrainInbox.noteHeader(title: "A", date: "d", source: "s", template: " \n \n") == "# A\n\n")
        check("header's own newlines trimmed",
              BrainInbox.noteHeader(title: "A", date: "d", source: "s", template: "\nby {source}\n\n") == "# A\n\nby s\n\n")

        // MARK: Text capture (default config)

        let vault = try makeVault()
        let inbox = vault.appendingPathComponent("Inbox")
        let mdName = "Résumé de réunion.md"
        let md = try source(mdName, Data("Hello\nworld".utf8))
        let note = try BrainInbox.save(fileURL: md, name: mdName, vault: vault, date: date)
        check("text note in the inbox, dated and slugged",
              note.path == inbox.appendingPathComponent("2026-10-15_resume-de-reunion.md").path, note.path)
        let body = read(note)
        check("text note starts with the title", firstLine(note) == "# Résumé de réunion", firstLine(note))
        check("text note has no frontmatter", !body.hasPrefix("---"))
        check("text note has the default header",
              body.hasPrefix("# Résumé de réunion\n\n- Captured: 2026-10-15\n- Source: Coucou — \(mdName)\n\n"), body)
        check("text note carries the original text", body.hasSuffix("\n\nHello\nworld\n"), body)
        check("text note is counted as unprocessed", pending(vault) == 1)

        let again = try BrainInbox.save(fileURL: md, name: mdName, vault: vault, date: date)
        let third = try BrainInbox.save(fileURL: md, name: mdName, vault: vault, date: date)
        check("second capture gets -2", again.lastPathComponent == "2026-10-15_resume-de-reunion-2.md", again.path)
        check("third capture gets -3", third.lastPathComponent == "2026-10-15_resume-de-reunion-3.md", third.path)
        check("first note left untouched", read(note) == body)

        let fmName = "with-frontmatter.markdown"
        let withFrontmatter = try source(fmName, Data("---\ntitle: x\n---\nbody".utf8))
        let fmNote = try BrainInbox.save(fileURL: withFrontmatter, name: fmName, vault: vault, date: date)
        check("a source with frontmatter still makes an unprocessed note",
              firstLine(fmNote) == "# with-frontmatter" && !BrainStatusScanner.hasFrontmatter(fmNote), read(fmNote))
        check(".markdown is inlined", read(fmNote).hasSuffix("body\n"))

        let upperName = "README-FIRST.TXT"
        let upper = try source(upperName, Data("text".utf8))
        let upperNote = try BrainInbox.save(fileURL: upper, name: upperName, vault: vault, date: date)
        check("upper-case .TXT is inlined", read(upperNote).hasSuffix("\n\ntext\n"), read(upperNote))

        // A note the user already has under that name is never overwritten.
        try Data("keep".utf8).write(to: inbox.appendingPathComponent("2026-10-15_idea.md"))
        let ideaName = "idea.txt"
        let idea = try source(ideaName, Data("new".utf8))
        let ideaNote = try BrainInbox.save(fileURL: idea, name: ideaName, vault: vault, date: date)
        check("existing note kept", read(inbox.appendingPathComponent("2026-10-15_idea.md")) == "keep")
        check("new note takes -2", ideaNote.lastPathComponent == "2026-10-15_idea-2.md", ideaNote.path)

        // MARK: Attached capture (default config)

        let pngName = "Beach photo.png"
        let pngBytes = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x01, 0xFF])
        let png = try source(pngName, pngBytes)
        let pngNote = try BrainInbox.save(fileURL: png, name: pngName, vault: vault, date: date)
        let attached = vault.appendingPathComponent("Inbox/attachments/Beach photo.png")
        check("binary note named after the file", pngNote.lastPathComponent == "2026-10-15_beach-photo.md", pngNote.path)
        check("binary copied under Inbox/attachments", (try? Data(contentsOf: attached)) == pngBytes)
        check("binary note embeds the attachment",
              read(pngNote).hasSuffix("\n\n![[Inbox/attachments/Beach photo.png]]\n"), read(pngNote))
        check("binary note starts with the title", firstLine(pngNote) == "# Beach photo")
        check("binary note has no frontmatter", !BrainStatusScanner.hasFrontmatter(pngNote))
        check("original file left in place", fm.fileExists(atPath: png.path))

        let pngAgain = try BrainInbox.save(fileURL: png, name: pngName, vault: vault, date: date)
        check("second attachment gets -2", fm.fileExists(atPath: vault.appendingPathComponent("Inbox/attachments/Beach photo-2.png").path))
        check("second binary note gets -2", pngAgain.lastPathComponent == "2026-10-15_beach-photo-2.md", pngAgain.path)
        check("second note embeds the -2 attachment",
              read(pngAgain).contains("![[Inbox/attachments/Beach photo-2.png]]"), read(pngAgain))
        check("first attachment untouched", (try? Data(contentsOf: attached)) == pngBytes)

        let fakeTextName = "dump.txt"
        let fakeText = try source(fakeTextName, Data([0x61, 0x00, 0x62]))
        let fakeNote = try BrainInbox.save(fileURL: fakeText, name: fakeTextName, vault: vault, date: date)
        check("a .txt that isn't text is attached", read(fakeNote).contains("![[Inbox/attachments/dump.txt]]"), read(fakeNote))

        let oddName = "Report #1 [v2].pdf"
        let odd = try source(oddName, Data("%PDF-1.7".utf8))
        let oddNote = try BrainInbox.save(fileURL: odd, name: oddName, vault: vault, date: date)
        check("embed uses the cleaned attachment name",
              read(oddNote).contains("![[Inbox/attachments/Report -1 -v2-.pdf]]"), read(oddNote))
        check("source line keeps the original name", read(oddNote).contains("— \(oddName)\n"))

        // Every capture so far is a pending inbox note (plus the user's "keep" note);
        // the attachments folder inside the inbox is not counted.
        let notesInInbox = try fm.contentsOfDirectory(atPath: inbox.path).filter { $0.hasSuffix(".md") }.count
        check("scanner counts every capture", pending(vault) == notesInInbox,
              "\(String(describing: pending(vault))) vs \(notesInInbox)")

        // MARK: Custom config

        let custom = BrainConfig.Inbox(folder: "Notes/New", attachments: "Files/dropped", ignore: ["index.md"],
                                       noteHeader: "Title: {title}\nFrom {source} on {date} {unknown}")
        let customVault = try makeVault(inbox: nil)
        let customNote = try BrainInbox.save(fileURL: md, name: mdName, vault: customVault, inbox: custom, date: date)
        check("custom inbox folder created and used",
              customNote.path == customVault.appendingPathComponent("Notes/New/2026-10-15_resume-de-reunion.md").path,
              customNote.path)
        check("custom header filled",
              read(customNote) == "# Résumé de réunion\n\nTitle: Résumé de réunion\nFrom \(mdName) on 2026-10-15 {unknown}\n\nHello\nworld\n",
              read(customNote))
        let customPng = try BrainInbox.save(fileURL: png, name: pngName, vault: customVault, inbox: custom, date: date)
        check("custom attachments folder", fm.fileExists(atPath: customVault.appendingPathComponent("Files/dropped/Beach photo.png").path))
        check("embed is relative to the vault", read(customPng).hasSuffix("\n\n![[Files/dropped/Beach photo.png]]\n"), read(customPng))
        check("custom inbox counted", pending(customVault, custom) == 2, String(describing: pending(customVault, custom)))
        check("nothing written to the default folders", !fm.fileExists(atPath: customVault.appendingPathComponent("Inbox").path))

        let headless = BrainConfig.Inbox(noteHeader: "")
        let headlessVault = try makeVault()
        let headlessNote = try BrainInbox.save(fileURL: md, name: mdName, vault: headlessVault, inbox: headless, date: date)
        check("empty header: title, blank line, text", read(headlessNote) == "# Résumé de réunion\n\nHello\nworld\n",
              read(headlessNote))
        let headlessPng = try BrainInbox.save(fileURL: png, name: pngName, vault: headlessVault, inbox: headless, date: date)
        check("empty header: title then embed",
              read(headlessPng) == "# Beach photo\n\n![[Inbox/attachments/Beach photo.png]]\n", read(headlessPng))

        let trickyName = "{date}.txt"
        let tricky = try source(trickyName, Data("x".utf8))
        let trickyNote = try BrainInbox.save(fileURL: tricky, name: trickyName, vault: headlessVault,
                                             inbox: BrainConfig.Inbox(noteHeader: "{source}"), date: date)
        check("a file named like a placeholder stays as named", read(trickyNote).hasPrefix("# {date}\n\n{date}.txt\n\n"),
              read(trickyNote))

        // MARK: Folders and errors

        let bare = try makeVault(inbox: nil)
        let bareNote = try BrainInbox.save(fileURL: md, name: mdName, vault: bare, date: date)
        check("inbox folder created when missing",
              bareNote.deletingLastPathComponent().lastPathComponent == "Inbox" && fm.fileExists(atPath: bareNote.path))

        let missing = root.appendingPathComponent("no-such-vault")
        do {
            try BrainInbox.save(fileURL: md, name: mdName, vault: missing, date: date)
            check("missing vault throws", false)
        } catch let error as BrainInboxError {
            check("missing vault throws vaultMissing", error == .vaultMissing, "\(error)")
        }
        check("missing vault not created", !fm.fileExists(atPath: missing.path))

        let folder = sources.appendingPathComponent("project", isDirectory: true)
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        do {
            try BrainInbox.save(fileURL: folder, name: "project", vault: vault, date: date)
            check("a folder throws", false)
        } catch let error as BrainInboxError {
            check("a folder throws folderNotSupported", error == .folderNotSupported, "\(error)")
        }
        check("errors carry a message", BrainInboxError.vaultMissing.errorDescription?.isEmpty == false)

        // The note can't be written (read-only inbox): the attachment copied for it is removed.
        let blockedInbox = BrainConfig.Inbox(folder: "Locked", attachments: "Files")
        let blocked = try makeVault(inbox: blockedInbox.folder)
        let locked = blocked.appendingPathComponent(blockedInbox.folder)
        try fm.setAttributes([.posixPermissions: 0o555], ofItemAtPath: locked.path)
        defer { try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.path) }
        do {
            try BrainInbox.save(fileURL: png, name: pngName, vault: blocked, inbox: blockedInbox, date: date)
            check("a read-only inbox throws", false)
        } catch {
            check("a read-only inbox throws", !(error is BrainInboxError), "\(error)")
        }
        let leftovers = (try? fm.contentsOfDirectory(atPath: blocked.appendingPathComponent("Files").path)) ?? ["<no folder>"]
        check("no attachment left behind", leftovers.isEmpty, "\(leftovers)")

        print("Brain inbox: \(cases) cases passed")
    }
}
