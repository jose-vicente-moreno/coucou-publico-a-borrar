import Foundation

// MARK: - VoiceGenderNames tests
//
// Pure test. Compiles with:
//   swiftc -o /tmp/voice-gender-tests \
//     NotchBuddy/Sources/App/Voice/VoiceGenderNames.swift \
//     tests/VoiceGenderTests.swift

@main
enum VoiceGenderTests {
    static var pass = 0
    static var fail = 0

    static func main() {
        check("Ava Premium", VoiceGenderNames.gender(name: "Ava (Premium)", identifier: "com.apple.voice.premium.en-US.Ava"), "female")
        check("Zoe Enhanced", VoiceGenderNames.gender(name: "Zoe (Enhanced)", identifier: "com.apple.voice.enhanced.en-US.Zoe"), "female")
        check("Jamie Premium", VoiceGenderNames.gender(name: "Jamie (Premium)", identifier: "com.apple.voice.premium.en-GB.Jamie"), "male")
        check("Evan", VoiceGenderNames.gender(name: "Evan", identifier: "com.apple.voice.enhanced.en-US.Evan"), "male")
        check("Amélie accent", VoiceGenderNames.gender(name: "Amélie", identifier: "com.apple.voice.compact.fr-CA.Amelie"), "female")
        check("Thomas", VoiceGenderNames.gender(name: "Thomas", identifier: "com.apple.voice.compact.fr-FR.Thomas"), "male")
        check("Siri female id", VoiceGenderNames.gender(name: "Siri Voice 2", identifier: "com.apple.ttsbundle.siri_female_en-US_compact"), "female")
        check("Siri male id", VoiceGenderNames.gender(name: "Siri Voice 1", identifier: "com.apple.ttsbundle.siri_male_en-US_compact"), "male")
        check("unknown", VoiceGenderNames.gender(name: "Zarvox", identifier: "com.apple.speech.synthesis.voice.Zarvox"), nil)
        check("Mónica accent", VoiceGenderNames.gender(name: "Mónica", identifier: "com.apple.voice.compact.es-ES.Monica"), "female")
        check("Paulina", VoiceGenderNames.gender(name: "Paulina (Enhanced)", identifier: "com.apple.voice.enhanced.es-MX.Paulina"), "female")
        check("Marisol Premium", VoiceGenderNames.gender(name: "Marisol (Premium)", identifier: "com.apple.voice.premium.es-ES.Marisol"), "female")
        check("Angélica", VoiceGenderNames.gender(name: "Angélica", identifier: "com.apple.voice.compact.es-MX.Angelica"), "female")
        check("Jorge", VoiceGenderNames.gender(name: "Jorge", identifier: "com.apple.voice.compact.es-ES.Jorge"), "male")
        check("Juan Enhanced", VoiceGenderNames.gender(name: "Juan (Enhanced)", identifier: "com.apple.voice.enhanced.es-MX.Juan"), "male")
        check("Diego", VoiceGenderNames.gender(name: "Diego", identifier: "com.apple.voice.compact.es-AR.Diego"), "male")

        print("\n\(pass)/\(pass + fail) passed.")
        if fail > 0 { exit(1) }
    }

    static func check<T: Equatable>(_ name: String, _ got: T, _ want: T) {
        if got == want { pass += 1; print("✓  \(name)") }
        else { fail += 1; print("✗  \(name) — got \(got), want \(want)") }
    }
}
