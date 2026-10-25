import Foundation

@main
enum VoiceConversationTests {

    static func main() {
        let phrases = TurnEndPolicy.conversationEndPhrases

        // ── Members ───────────────────────────────────────────────────────────
        precondition(phrases.contains("stop"),          "stop must end conversation")
        precondition(phrases.contains("merci"),         "merci must end conversation")
        precondition(phrases.contains("annule"),        "annule must end conversation")
        precondition(phrases.contains("annuler"),       "annuler must end conversation")
        precondition(phrases.contains("cancel"),        "cancel must end conversation")
        precondition(phrases.contains("never mind"),    "never mind must end conversation")
        precondition(phrases.contains("bye"),           "bye must end conversation")
        precondition(phrases.contains("au revoir"),     "au revoir must end conversation")
        precondition(phrases.contains("c est bon"),     "c est bon must end conversation")
        precondition(phrases.contains("c'est bon"),     "c'est bon must end conversation")
        precondition(phrases.contains("that s all"),    "that s all must end conversation")
        precondition(phrases.contains("that's all"),    "that's all must end conversation")
        precondition(phrases.contains("laisse tomber"), "laisse tomber must end conversation")

        // Spanish (WakePhrase.normalise keeps accents: both spellings)
        for p in ["gracias", "eso es todo", "ya está", "ya esta", "nada más", "nada mas", "déjalo", "dejalo",
                  "olvídalo", "cancela", "adiós", "adios", "hasta luego"] {
            precondition(phrases.contains(p), "\(p) must end conversation")
        }

        // ── Non-members ───────────────────────────────────────────────────────
        precondition(!phrases.contains("xyz"),              "xyz must NOT end conversation")
        precondition(!phrases.contains("ajoute"),           "ajoute must NOT end conversation")
        precondition(!phrases.contains("merci beaucoup"),   "merci beaucoup must NOT end conversation")
        precondition(!phrases.contains("para"),             "para (also 'for') must NOT end conversation")
        precondition(!phrases.contains("muchas gracias por la ayuda"), "a whole sentence must NOT end conversation")

        // ── Non-empty ─────────────────────────────────────────────────────────
        precondition(!phrases.isEmpty, "conversationEndPhrases must not be empty")

        print("All voice conversation end-phrase tests passed.")
    }
}
