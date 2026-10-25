import Foundation

/// Whether the user is already looking at the app the session runs in.
///
/// When they are, a finish or an error is in front of them already, so the pill takes a
/// badge and stays quiet: no sound, no reveal. Upstream decides this from `hostApp`
/// alone (`fix/quiet-when-terminal-in-front`), which works there because a session whose
/// terminal cannot be named is dropped before this point.
///
/// Coucou no longer drops those sessions, so the test has to cope with `hostApp == nil`.
/// Two different situations arrive with no host:
///
/// - A terminal Coucou does not recognise. The hook still reports its `bundle_id`, the
///   user really is sitting in front of it, and announcing the finish would be noise.
/// - A headless run (`claude -p`, a background job, a launchd task). It reports no app at
///   all, nobody is watching it, and announcing the finish is the entire point.
///
/// Falling back to the reported bundle id separates the two without a special case: the
/// first has an app to compare, the second has none and is never "in front".
///
/// A pure function of three strings on purpose, so it can be tested without AppKit.
///
/// - Parameters:
///   - hostApp: bundle id of the terminal Coucou identified, or nil when it could not.
///   - bundleId: bundle id the hook reported for the client; empty when headless.
///   - frontmost: bundle id of the frontmost application, or nil when there is none.
func sessionTerminalIsInFront(hostApp: String?, bundleId: String, frontmost: String?) -> Bool {
    let sessionApp = hostApp ?? (bundleId.isEmpty ? nil : bundleId)
    guard let sessionApp, let frontmost else { return false }
    return sessionApp == frontmost
}
