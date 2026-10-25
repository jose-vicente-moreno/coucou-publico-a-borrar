import Foundation

@main
enum TurnEndPolicyTests {
    static func main() {
        // baseSilence for empty transcript
        precondition(TurnEndPolicy.silenceDelay(for: "") == TurnEndPolicy.baseSilence,
            "empty → baseSilence")

        // baseSilence for normal word
        precondition(TurnEndPolicy.silenceDelay(for: "mets gemini") == TurnEndPolicy.baseSilence,
            "normal word → baseSilence")

        // extendedSilence for conjunction
        precondition(TurnEndPolicy.silenceDelay(for: "mets gemini et") == TurnEndPolicy.extendedSilence,
            "ends with 'et' → extendedSilence")

        // extendedSilence for article
        precondition(TurnEndPolicy.silenceDelay(for: "ajoute le") == TurnEndPolicy.extendedSilence,
            "ends with 'le' → extendedSilence")

        // extendedSilence for bare verb
        precondition(TurnEndPolicy.silenceDelay(for: "ajoute") == TurnEndPolicy.extendedSilence,
            "bare action verb → extendedSilence")

        // extendedSilence for EN conjunction
        precondition(TurnEndPolicy.silenceDelay(for: "add github and") == TurnEndPolicy.extendedSilence,
            "ends with 'and' → extendedSilence")

        // baseSilence for complete command
        precondition(TurnEndPolicy.silenceDelay(for: "ajoute github") == TurnEndPolicy.baseSilence,
            "complete command → baseSilence")

        // Constants
        precondition(TurnEndPolicy.baseSilence == 1.6,    "baseSilence == 1.6")
        precondition(TurnEndPolicy.extendedSilence == 2.6, "extendedSilence == 2.6")
        precondition(TurnEndPolicy.silenceDelay(for: "l objet c est", longAnswer: true) == TurnEndPolicy.answerSilence,
            "free-text answer → answerSilence")
        precondition(TurnEndPolicy.silenceDelay(for: "mets euh") == TurnEndPolicy.extendedSilence,
            "ends with 'euh' → extendedSilence")
        precondition(TurnEndPolicy.maxTurnTime == 15.0,    "maxTurnTime == 15.0")

        // Spanish
        precondition(TurnEndPolicy.silenceDelay(for: "anade github y") == TurnEndPolicy.extendedSilence,
            "ends with 'y' → extendedSilence")
        precondition(TurnEndPolicy.silenceDelay(for: "pon musica en") == TurnEndPolicy.extendedSilence,
            "ends with 'en' → extendedSilence")
        precondition(TurnEndPolicy.silenceDelay(for: "quita") == TurnEndPolicy.extendedSilence,
            "bare Spanish verb → extendedSilence")
        precondition(TurnEndPolicy.silenceDelay(for: "anade github") == TurnEndPolicy.baseSilence,
            "complete Spanish command → baseSilence")
        precondition(TurnEndPolicy.silenceDelay(for: "para") == TurnEndPolicy.baseSilence,
            "'para' (stop) stays quick → baseSilence")

        print("TurnEndPolicyTests: all cases passed")
    }
}
