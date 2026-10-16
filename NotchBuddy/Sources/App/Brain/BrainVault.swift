#if !APPSTORE
import Foundation

/// The user's "brain": the knowledge vault the Claude Code chat runs in
/// (Settings → Chat → Brain folder). Foundation only, so the tests can use it.
enum BrainVault {
    /// The folder at `path` (a leading `~` is expanded) when it is set and is a
    /// directory; nil when unset, gone or a plain file.
    static func url(path: String) -> URL? {
        let expanded = (path.trimmingCharacters(in: .whitespacesAndNewlines) as NSString).expandingTildeInPath
        guard !expanded.isEmpty else { return nil }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: expanded, isDirectory: &isDirectory),
              isDirectory.boolValue else { return nil }
        return URL(fileURLWithPath: expanded, isDirectory: true)
    }

    /// Unreserved ASCII plus `/`: everything else in the path is percent-encoded
    /// (spaces, accents, `&`, `#`…), so the link survives any folder name.
    private static let pathAllowed = CharacterSet(
        charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~/")

    /// `obsidian://open?path=<vault>`: Obsidian opens the vault that holds this folder.
    static func obsidianURL(for vault: URL) -> URL? {
        guard let encoded = vault.standardizedFileURL.path.addingPercentEncoding(withAllowedCharacters: pathAllowed)
        else { return nil }
        return URL(string: "obsidian://open?path=\(encoded)")
    }
}
#endif
