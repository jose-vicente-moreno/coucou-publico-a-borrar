#if !APPSTORE
import Foundation

// MARK: - ElevenLabsTTS
//
// Optional voice for Coucou's answers (Settings → Voice → ElevenLabs), with the user's
// own API key stored in the Keychain ("elevenlabs-api-key"). Network only to
// api.elevenlabs.io, only while Coucou speaks.
//
// No voice ID is hard-coded: ElevenLabs' old default voices expire on 31 Dec 2026 and
// newer accounts don't have them. Coucou lists the voices of the user's account and
// picks the first one of the chosen gender (female by default) in the answer's language,
// English when the account has none in it, then caches it per gender and language.

@MainActor
final class ElevenLabsTTS {
    static let shared = ElevenLabsTTS()

    static let keyName = "elevenlabs-api-key"
    private static let model = "eleven_flash_v2_5"   // low-latency model

    static var isActive: Bool {
        VoiceSettings.ttsEngine == "elevenlabs" && KeychainStore.shared.get(keyName) != nil
    }

    struct Voice: Equatable { let id: String; let name: String }
    private var chosen: (gender: String, language: String, voice: Voice)?

    /// Name of the voice in use, for Settings ("Rachel", "Talia – Warm Soft Guide"…).
    var currentVoiceName: String? { chosen?.voice.name }

    /// Forget the cached voice (gender, language or key changed).
    func reset() { chosen = nil }

    /// MP3 for one sentence, or nil (no key, network error, quota…) → Mac voice instead.
    func audio(for text: String, locale: Locale?) async -> Data? {
        let language = locale?.language.languageCode?.identifier ?? VoiceSettings.language
        guard let key = KeychainStore.shared.get(Self.keyName),
              let voice = await voice(key: key, language: language) else { return nil }
        var comps = URLComponents(string: "https://api.elevenlabs.io/v1/text-to-speech/\(voice.id)")!
        comps.queryItems = [URLQueryItem(name: "output_format", value: "mp3_44100_128")]
        guard let url = comps.url else { return nil }
        var req = URLRequest(url: url, timeoutInterval: 8)
        req.httpMethod = "POST"
        req.setValue(key, forHTTPHeaderField: "xi-api-key")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("audio/mpeg", forHTTPHeaderField: "Accept")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["text": text, "model_id": Self.model])
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200, !data.isEmpty else {
            appendAppLog("nb.log", "[Voice] ElevenLabs request failed, Mac voice used")
            return nil
        }
        return data
    }

    /// The voice for the chosen gender and the language, looked up once in the user's account.
    func voice(key: String, language: String) async -> Voice? {
        let gender = VoiceSettings.elevenGender
        if let c = chosen, c.gender == gender, c.language == language { return c.voice }
        var req = URLRequest(url: URL(string: "https://api.elevenlabs.io/v1/voices")!, timeoutInterval: 8)
        req.setValue(key, forHTTPHeaderField: "xi-api-key")
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let voices = json["voices"] as? [[String: Any]] else {
            appendAppLog("nb.log", "[Voice] ElevenLabs voice list unavailable")
            return nil
        }
        guard let v = Self.pick(voices, gender: gender, language: language) else { return nil }
        chosen = (gender, language, v)
        return v
    }

    /// Accents that tell a voice's language when its labels have no "language".
    nonisolated private static let accents: [String: [String]] = [
        "en": ["american", "british", "australian", "irish", "english", "us", "uk"],
        "fr": ["french", "france", "parisian", "quebec"],
        "es": ["spanish", "spain", "castilian", "mexican", "latin", "argentin", "colombian", "chilean"],
    ]

    /// First voice of the gender in `language` ("fr", "es"…; a young one first for a man);
    /// else the first English one; else any voice of the gender; else the first one.
    nonisolated static func pick(_ voices: [[String: Any]], gender: String, language: String = "en") -> Voice? {
        func labels(_ v: [String: Any]) -> [String: String] { v["labels"] as? [String: String] ?? [:] }
        func speaks(_ v: [String: Any], _ lang: String) -> Bool {
            let l = labels(v)
            if let code = l["language"] { return code.lowercased().hasPrefix(lang) }
            let accent = (l["accent"] ?? "").lowercased()
            // No accent said: ElevenLabs' own voices, English.
            if accent.isEmpty { return lang == "en" }
            return (accents[lang] ?? []).contains { accent.contains($0) }
        }
        func isYoung(_ v: [String: Any]) -> Bool { (labels(v)["age"] ?? "").lowercased().contains("young") }
        let ofGender = voices.filter { labels($0)["gender"]?.lowercased() == gender }
        let native = language == "en" ? [] : ofGender.filter { speaks($0, language) }
        let pool = native.isEmpty ? ofGender.filter { speaks($0, "en") } : native
        // Male: a young voice first, it sounds closer to Coucou than a deep narrator.
        let young = gender == "male" ? pool.first(where: isYoung) : nil
        let v = young ?? pool.first ?? ofGender.first ?? voices.first
        guard let v, let id = v["voice_id"] as? String else { return nil }
        return Voice(id: id, name: v["name"] as? String ?? id)
    }
}
#endif
