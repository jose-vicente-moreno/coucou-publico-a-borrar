import Foundation

/// Request building, voice list parsing and voice choice for the VoiceStudio engine.
@main
enum VoiceStudioAPITests {
    static func main() {
        var cases = 0
        func check(_ name: String, _ condition: Bool, _ detail: @autoclosure () -> String = "") {
            precondition(condition, "\(name) failed \(detail())")
            cases += 1
        }
        typealias V = VoiceStudioAPI.Voice

        check("default address", VoiceStudioAPI.normalised("") == "http://127.0.0.1:3900")
        check("trailing slash and /v1 dropped", VoiceStudioAPI.normalised(" http://box:3900/v1/ ") == "http://box:3900")
        check("speech URL", VoiceStudioAPI.speechURL(base: "http://127.0.0.1:3900/")?.absoluteString
              == "http://127.0.0.1:3900/v1/audio/speech")
        check("voices URL", VoiceStudioAPI.voicesURL(base: "http://127.0.0.1:3900")?.absoluteString
              == "http://127.0.0.1:3900/v1/audio/voices")

        let body = VoiceStudioAPI.speechBody(text: "Hola, ¿qué tal?", voice: "es_female_1")
            .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        check("OpenAI speech fields", body?["model"] as? String == "tts-1" && body?["voice"] as? String == "es_female_1"
              && body?["input"] as? String == "Hola, ¿qué tal?" && body?["response_format"] as? String == "wav",
              "\(String(describing: body))")

        func parse(_ json: String) -> [V] { VoiceStudioAPI.parseVoices(Data(json.utf8)) }
        check("plain string list", parse(#"["alloy","nova"]"#).map(\.id) == ["alloy", "nova"])
        check("voices key with objects",
              parse(#"{"voices":[{"id":"v1","name":"Lucía","language":"es-ES","gender":"Female"}]}"#)
                == [V(id: "v1", name: "Lucía", language: "es-ES", gender: "female")])
        check("data key, voice_id and lang",
              parse(#"{"data":[{"voice_id":"v2","lang":"fr"}]}"#) == [V(id: "v2", name: "v2", language: "fr", gender: nil)])
        check("entries without id skipped", parse(#"[{"language":"es"},"ok"]"#).map(\.id) == ["ok"])
        check("not JSON", parse("<html>").isEmpty)

        let list = [
            V(id: "en-f", name: "Ava", language: "en-US", gender: "female"),
            V(id: "es-m", name: "Jorge", language: "es-ES", gender: "male"),
            V(id: "es-f", name: "Lucía", language: "es_MX", gender: "female"),
            V(id: "x", name: "Raw", language: nil, gender: nil),
        ]
        check("saved voice kept", VoiceStudioAPI.pick(list, saved: "x", language: "es", gender: "female")?.id == "x")
        check("language and gender", VoiceStudioAPI.pick(list, saved: "", language: "es", gender: "female")?.id == "es-f")
        check("language when no gender match", VoiceStudioAPI.pick(list, saved: "", language: "es", gender: "other")?.id == "es-m")
        check("saved voice gone: by language", VoiceStudioAPI.pick(list, saved: "gone", language: "en", gender: "male")?.id == "en-f")
        check("no language match: first voice", VoiceStudioAPI.pick(list, saved: "", language: "de", gender: "female")?.id == "en-f")
        check("'es' does not match 'est'", VoiceStudioAPI.pick([V(id: "et", name: "", language: "est", gender: nil)],
                                                              saved: "", language: "es", gender: "")?.id == "et")
        check("empty list", VoiceStudioAPI.pick([], saved: "", language: "es", gender: "female") == nil)

        print("VoiceStudioAPITests: \(cases) cases passed")
    }
}
