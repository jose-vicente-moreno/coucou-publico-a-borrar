#if !APPSTORE
import Foundation

// MARK: - VoiceStudioAPI
//
// The pure part of the local voice engine: request bodies, the voice list and the
// choice of a voice. VoiceStudio (github.com/debpalash/VoiceStudio) serves an
// OpenAI-compatible `POST /v1/audio/speech` on http://127.0.0.1:3900, with no key on
// loopback; any other OpenAI-compatible speech server works the same way.

enum VoiceStudioAPI {
    static let defaultBaseURL = "http://127.0.0.1:3900"

    struct Voice: Equatable, Sendable {
        let id: String
        let name: String
        let language: String?   // "es", "en-US"… when the server says
        let gender: String?     // "female" / "male" when the server says
    }

    /// `base` without trailing slashes or a pasted `/v1`.
    static func normalised(_ base: String) -> String {
        var s = base.trimmingCharacters(in: .whitespacesAndNewlines)
        while s.hasSuffix("/") { s.removeLast() }
        if s.hasSuffix("/v1") { s.removeLast(3) }
        return s.isEmpty ? defaultBaseURL : s
    }

    static func speechURL(base: String) -> URL? { URL(string: normalised(base) + "/v1/audio/speech") }
    static func voicesURL(base: String) -> URL? { URL(string: normalised(base) + "/v1/audio/voices") }

    /// OpenAI's speech request, WAV out (no decoder needed: AVAudioPlayer plays it).
    static func speechBody(text: String, voice: String) -> Data? {
        try? JSONSerialization.data(withJSONObject: [
            "model": "tts-1", "voice": voice, "input": text, "response_format": "wav",
        ])
    }

    /// Accepts the shapes speech servers use: `["alloy", …]`, `{"voices": [...]}`,
    /// `{"data": [...]}`, entries as strings or objects (id / voice_id / name,
    /// language / lang / locale, gender).
    static func parseVoices(_ data: Data) -> [Voice] {
        guard let json = try? JSONSerialization.jsonObject(with: data) else { return [] }
        let list: [Any]
        if let array = json as? [Any] { list = array }
        else if let object = json as? [String: Any] {
            list = object["voices"] as? [Any] ?? object["data"] as? [Any] ?? []
        } else { list = [] }
        return list.compactMap { entry in
            if let id = entry as? String { return Voice(id: id, name: id, language: nil, gender: nil) }
            guard let object = entry as? [String: Any],
                  let id = (object["id"] ?? object["voice_id"] ?? object["name"]) as? String, !id.isEmpty
            else { return nil }
            let language = (object["language"] ?? object["lang"] ?? object["locale"]) as? String
            let gender = (object["gender"] as? String)?.lowercased()
            return Voice(id: id, name: object["name"] as? String ?? id, language: language, gender: gender)
        }
    }

    /// The saved voice when the server still has it; else the first voice in the
    /// answer's language and gender, then in its language, then the first one.
    static func pick(_ voices: [Voice], saved: String, language: String, gender: String) -> Voice? {
        if let kept = voices.first(where: { $0.id == saved }) { return kept }
        func speaks(_ v: Voice) -> Bool {
            guard let l = v.language?.lowercased() else { return false }
            return l == language || l.hasPrefix(language + "-") || l.hasPrefix(language + "_")
        }
        return voices.first { speaks($0) && $0.gender == gender }
            ?? voices.first(where: speaks)
            ?? voices.first
    }
}
#endif
