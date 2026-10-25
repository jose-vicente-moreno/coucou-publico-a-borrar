import Foundation

@main
enum TerminalFocusTests {
    static let terminal = "com.apple.Terminal"
    static let ghostty = "com.mitchellh.ghostty"
    static let coucou = "com.coucou.NotchBuddy"

    static func main() {
        // Upstream's case: Coucou named the terminal and it is the frontmost app.
        // The user is watching the session finish, so the pill stays quiet.
        precondition(sessionTerminalIsInFront(
            hostApp: terminal, bundleId: terminal, frontmost: terminal))

        // Named terminal, but the user has moved to another app: announce the finish.
        precondition(!sessionTerminalIsInFront(
            hostApp: terminal, bundleId: terminal, frontmost: coucou))

        // A terminal Coucou does not recognise, so no hostApp, but the hook still
        // reported its bundle id and the user is in it. This is the case upstream's
        // test gets wrong, and the one the routing fix made common.
        precondition(sessionTerminalIsInFront(
            hostApp: nil, bundleId: ghostty, frontmost: ghostty))

        // Same unrecognised terminal, user elsewhere: announce it.
        precondition(!sessionTerminalIsInFront(
            hostApp: nil, bundleId: ghostty, frontmost: coucou))

        // Headless run: no host, no bundle id. Nobody is watching, so it is never
        // "in front" and the finish is always announced. This is the whole point of
        // tracking background sessions, so it must not be silenced by accident.
        precondition(!sessionTerminalIsInFront(
            hostApp: nil, bundleId: "", frontmost: terminal))

        // Headless run with nothing frontmost either (login window, all apps hidden):
        // still announced, and no crash on the nil.
        precondition(!sessionTerminalIsInFront(
            hostApp: nil, bundleId: "", frontmost: nil))

        // An empty bundle id must never match an empty frontmost id: two unknowns are
        // not the same app. Without the isEmpty guard this would silence every
        // headless session.
        precondition(!sessionTerminalIsInFront(
            hostApp: nil, bundleId: "", frontmost: ""))

        // A named host wins over a client bundle id that differs: the session runs in
        // the terminal, not in the editor that spawned it.
        precondition(sessionTerminalIsInFront(
            hostApp: terminal, bundleId: ghostty, frontmost: terminal))
        precondition(!sessionTerminalIsInFront(
            hostApp: terminal, bundleId: ghostty, frontmost: ghostty))

        // Nothing frontmost while a real terminal is known: not in front.
        precondition(!sessionTerminalIsInFront(
            hostApp: terminal, bundleId: terminal, frontmost: nil))

        print("TerminalFocusTests: all passed")
    }
}
