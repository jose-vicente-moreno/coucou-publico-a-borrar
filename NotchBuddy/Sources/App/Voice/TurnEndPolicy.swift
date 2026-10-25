#if !APPSTORE
import Foundation

// MARK: - TurnEndPolicy
//
// Decides silence duration before ending a command turn.
// Standalone compilable (used by test scripts via swiftc).
enum TurnEndPolicy {
    static let baseSilence:     TimeInterval = 1.6
    static let extendedSilence: TimeInterval = 2.6
    /// Answers Coucou asked for in free text (who, subject, what the mail says, what to
    /// look up): room to think, a 2–3 s pause doesn't cut me off.
    static let answerSilence:   TimeInterval = 3.2
    static let maxTurnTime:     TimeInterval = 15.0

    /// Returns the silence timeout given the current *normalised* partial transcript.
    /// Call with `IntentParser.normalise(rawTranscript)`.
    static func silenceDelay(for transcript: String, longAnswer: Bool = false) -> TimeInterval {
        if longAnswer { return answerSilence }
        guard !transcript.trimmingCharacters(in: .whitespaces).isEmpty else {
            return baseSilence
        }
        let lastWord = transcript.split(separator: " ").last.map(String.init) ?? ""
        return extendingWords.contains(lastWord) ? extendedSilence : baseSilence
    }

    /// Phrases that end the conversation window.
    /// Single source of truth — used by VoiceEngine and IslandWindowController.
    static let conversationEndPhrases: Set<String> = [
        "merci", "c est bon", "c'est bon", "that s all", "that's all", "stop",
        "laisse tomber", "annule", "annuler", "cancel", "never mind", "bye", "au revoir",
        // Spanish (accents kept by WakePhrase.normalise: both spellings)
        "gracias", "eso es todo", "ya está", "ya esta", "nada más", "nada mas", "déjalo", "dejalo",
        "olvídalo", "olvidalo", "cancela", "cancelar", "adiós", "adios", "hasta luego",
    ]

    // Words that suggest the utterance is mid-thought and should get extra silence.
    static let extendingWords: Set<String> = [
        // FR conjunctions / linkers
        "et", "puis", "ensuite", "mais", "ou",
        // EN conjunctions
        "and", "then", "but", "or",
        // ES conjunctions
        "y", "o", "pero", "luego", "despues",
        // Thinking out loud ("euh…", "hmm", "genre")
        "euh", "heu", "hum", "hmm", "mmm", "bah", "ben", "bon", "genre", "enfin", "attends",
        "um", "uh", "uhm", "erm", "er", "like", "well", "wait",
        "eh", "em", "este", "pues", "bueno", "espera",
        // FR articles / prepositions
        "de", "du", "le", "la", "les", "des", "un", "une",
        "a", "au", "aux", "sur", "dans", "avec", "pour",
        // EN articles / prepositions
        "the", "to", "on", "of", "in", "at", "with", "for",
        // ES articles / prepositions ("para" left out: alone it is "stop")
        "el", "los", "las", "una", "del", "al", "en", "con", "por",
        // FR bare action verbs (imperative without object)
        "ajoute", "enleve", "retire", "supprime", "desactive", "active",
        "mets", "met", "lance", "joue", "balance", "demarre",
        "monte", "baisse", "coupe", "arrete",
        // EN bare action verbs
        "add", "remove", "disable", "enable", "play", "start",
        "increase", "decrease", "set",
        // ES bare action verbs
        "anade", "agrega", "quita", "elimina", "borra", "desactiva", "activa",
        "pon", "sube", "baja",
    ]
}
#endif
