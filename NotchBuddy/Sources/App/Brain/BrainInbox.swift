#if !APPSTORE
import Foundation

enum BrainInboxError: LocalizedError, Equatable {
    case vaultMissing
    case folderNotSupported
    case noFreeName(String)

    var errorDescription: String? {
        switch self {
        case .vaultMissing: "The brain folder can't be found."
        case .folderNotSupported: "Folders can't be saved to the brain, only files."
        case .noFreeName(let name): "Too many files named \(name) already."
        }
    }
}

/// Drops a file into the brain's inbox: a dated note without frontmatter (an
/// unprocessed one) in the config's inbox folder, with the text inline or the file
/// attached in its attachments folder. Never overwrites. Foundation only, so the
/// tests can run it on a fake vault.
enum BrainInbox {
    /// Copied into the note; anything else is attached.
    static let textExtensions: Set<String> = ["md", "markdown", "txt"]
    static let maxSlugLength = 60
    /// Used when the file name has nothing to slug (only symbols, say).
    static let fallbackSlug = "note"
    /// `-2` … `-999`, then give up.
    private static let maxCopies = 999
    /// Characters that break an `![[embed]]` (heading, block, alias, link).
    private static let wikilinkBreakers = CharacterSet(charactersIn: "[]#^|\\")
    /// Any script to Latin, then to plain ASCII (é → e, ß → ss, Привет → Privet).
    private static let toASCII = StringTransform("Any-Latin; Latin-ASCII")

    /// Saves `fileURL` (shown to the user as `name`) into `vault` and returns the new note.
    @discardableResult
    static func save(fileURL: URL, name: String, vault: URL, inbox config: BrainConfig.Inbox = BrainConfig.default.inbox,
                     date: Date = Date()) throws -> URL {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: vault.path, isDirectory: &isDirectory),
              isDirectory.boolValue else { throw BrainInboxError.vaultMissing }
        // A bundle (.key, .pages…) is one document; a plain folder could be a whole project.
        let kind = try? fileURL.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey])
        if kind?.isDirectory == true, kind?.isPackage != true { throw BrainInboxError.folderNotSupported }

        let stamp = dateStamp(date)
        let stem = (name as NSString).deletingPathExtension
        let header = noteHeader(title: title(fromStem: stem, fallback: name), date: stamp, source: name,
                                template: config.noteHeader)
        let noteBase = "\(stamp)_\(slug(stem))"
        let inbox = vault.appendingPathComponent(config.folder, isDirectory: true)
        try FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)

        if let text = inlineText(of: fileURL, name: name) {
            return try writeNote(header + text, in: inbox, base: noteBase)
        }
        let attachment = try copyAttachment(fileURL, name: name,
                                            to: vault.appendingPathComponent(config.attachments, isDirectory: true))
        do {
            let embed = "![[\(config.attachments)/\(attachment.lastPathComponent)]]"
            return try writeNote(header + embed, in: inbox, base: noteBase)
        } catch {
            try? FileManager.default.removeItem(at: attachment)
            throw error
        }
    }

    // MARK: - Naming

    /// "Résumé Q3 (final)" → "resume-q3-final": ASCII lowercase kebab-case, accents
    /// and other scripts transliterated, a leading date dropped (the note gets
    /// today's), at most `maxSlugLength` characters.
    static func slug(_ stem: String) -> String {
        let plain = (stem.applyingTransform(toASCII, reverse: false) ?? stem).lowercased()
        var words: [String] = []
        var word = ""
        for scalar in plain.unicodeScalars {
            if scalar.isASCII, CharacterSet.alphanumerics.contains(scalar) {
                word.unicodeScalars.append(scalar)
            } else if !word.isEmpty {
                words.append(word)
                word = ""
            }
        }
        if !word.isEmpty { words.append(word) }
        if words.count > 3, words[0].count == 4, words[1].count == 2, words[2].count == 2,
           words[0...2].allSatisfy({ $0.allSatisfy(\.isNumber) }) {
            words.removeFirst(3)
        }
        var result = words.joined(separator: "-")
        if result.count > maxSlugLength {
            result = String(result.prefix(maxSlugLength))
            while result.hasSuffix("-") { result.removeLast() }
        }
        return result.isEmpty ? fallbackSlug : result
    }

    /// The note's heading: the file name without extension, underscores as spaces.
    static func title(fromStem stem: String, fallback: String) -> String {
        let words = stem.replacingOccurrences(of: "_", with: " ")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        return words.isEmpty ? fallback : words
    }

    /// YYYY-MM-DD in the user's time zone.
    static func dateStamp(_ date: Date) -> String {
        let parts = Calendar(identifier: .gregorian).dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// The attachment's file name: the original one, minus what would break the embed.
    static func attachmentName(_ name: String) -> String {
        var cleaned = String(String.UnicodeScalarView(name.unicodeScalars.map {
            wikilinkBreakers.contains($0) || $0 == "/" || $0 == ":" ? "-" : $0
        }))
        while cleaned.hasPrefix(".") { cleaned.removeFirst() }   // a dotfile would be hidden
        cleaned = cleaned.trimmingCharacters(in: .whitespaces)
        return cleaned.isEmpty ? fallbackSlug : cleaned
    }

    // MARK: - Note

    /// The title, then `template` with `{date}`, `{source}` and `{title}` filled in
    /// (none when it is blank), then a blank line before the body.
    static func noteHeader(title: String, date: String, source: String, template: String) -> String {
        let lines = fill(template, ["date": date, "source": source, "title": title]).trimmingCharacters(in: .newlines)
        let block = lines.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "" : "\(lines)\n\n"
        return "# \(title)\n\n\(block)"
    }

    /// `template` with each `{key}` of `values` replaced, in one pass (a file named
    /// "{date}.md" stays as is); any other `{…}` is kept as written.
    static func fill(_ template: String, _ values: [String: String]) -> String {
        var result = ""
        var rest = Substring(template)
        while let open = rest.firstIndex(of: "{") {
            result += rest[..<open]
            let body = rest[rest.index(after: open)...]
            guard let close = body.firstIndex(of: "}"), let value = values[String(body[..<close])] else {
                result += "{"
                rest = body
                continue
            }
            result += value
            rest = body[body.index(after: close)...]
        }
        return result + rest
    }

    /// The text of a `.md`/`.markdown`/`.txt` file; nil for any other file, or one
    /// that isn't text after all (then it's attached instead).
    private static func inlineText(of fileURL: URL, name: String) -> String? {
        guard textExtensions.contains((name as NSString).pathExtension.lowercased()),
              let data = try? Data(contentsOf: fileURL),
              let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1),
              !text.contains("\u{0}") else { return nil }
        return text
    }

    private static func writeNote(_ body: String, in inbox: URL, base: String) throws -> URL {
        let data = Data((body.hasSuffix("\n") ? body : body + "\n").utf8)
        for copy in 1...maxCopies {
            let url = inbox.appendingPathComponent(numbered(base, copy) + ".md")
            do {
                try data.write(to: url, options: .withoutOverwriting)
                return url
            } catch CocoaError.fileWriteFileExists {
                continue
            }
        }
        throw BrainInboxError.noFreeName(base + ".md")
    }

    private static func copyAttachment(_ fileURL: URL, name: String, to folder: URL) throws -> URL {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let cleaned = attachmentName(name)
        let stem = (cleaned as NSString).deletingPathExtension
        let ext = (cleaned as NSString).pathExtension
        for copy in 1...maxCopies {
            let candidate = numbered(stem, copy) + (ext.isEmpty ? "" : ".\(ext)")
            let url = folder.appendingPathComponent(candidate)
            do {
                try FileManager.default.copyItem(at: fileURL, to: url)
                return url
            } catch CocoaError.fileWriteFileExists {
                continue
            }
        }
        throw BrainInboxError.noFreeName(cleaned)
    }

    /// "name", "name-2", "name-3"…
    private static func numbered(_ base: String, _ copy: Int) -> String {
        copy == 1 ? base : "\(base)-\(copy)"
    }
}
#endif
