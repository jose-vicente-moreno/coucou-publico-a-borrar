#if !APPSTORE
import AppKit
import Foundation

// MARK: - VoiceStudioTTS
//
// Coucou's answers in a local open-source voice (Settings → Voice → VoiceStudio):
// VoiceStudio running on this Mac, no key, nothing leaves the machine. One WAV per
// sentence, like ElevenLabs. When the server doesn't answer, the Mac voice speaks and
// Coucou stops asking it for 30 s, so a closed VoiceStudio never slows a sentence down.

@MainActor
final class VoiceStudioTTS {
    static let shared = VoiceStudioTTS()
    static let bundleId = "com.voicestudio.desktop"

    static var isActive: Bool { VoiceSettings.ttsEngine == "voicestudio" }

    private var voices: [VoiceStudioAPI.Voice]?
    private var unreachableUntil: Date = .distantPast
    private static let retryAfter: TimeInterval = 30
    private static let timeout: TimeInterval = 8

    /// Forget the voice list (URL or voice changed in Settings).
    func reset() {
        voices = nil
        unreachableUntil = .distantPast
    }

    /// WAV for one sentence, or nil → the Mac voice says it.
    func audio(for text: String, locale: Locale?) async -> Data? {
        guard Date() >= unreachableUntil,
              let url = VoiceStudioAPI.speechURL(base: VoiceSettings.voiceStudioURL),
              let voice = await voice(for: locale),
              let body = VoiceStudioAPI.speechBody(text: text, voice: voice.id) else { return nil }
        var request = URLRequest(url: url, timeoutInterval: Self.timeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200, !data.isEmpty else {
            unreachableUntil = Date().addingTimeInterval(Self.retryAfter)
            appendAppLog("nb.log", "[Voice] VoiceStudio request failed, Mac voice used")
            return nil
        }
        return data
    }

    /// The server's voices (cached), for Settings and for picking one.
    func listVoices(refresh: Bool = false) async -> [VoiceStudioAPI.Voice]? {
        if let voices, !refresh { return voices }
        guard let url = VoiceStudioAPI.voicesURL(base: VoiceSettings.voiceStudioURL) else { return nil }
        guard let (data, response) = try? await URLSession.shared.data(for: URLRequest(url: url, timeoutInterval: 4)),
              (response as? HTTPURLResponse)?.statusCode == 200 else {
            unreachableUntil = Date().addingTimeInterval(Self.retryAfter)
            return nil
        }
        let parsed = VoiceStudioAPI.parseVoices(data)
        voices = parsed
        return parsed
    }

    private func voice(for locale: Locale?) async -> VoiceStudioAPI.Voice? {
        let language = locale?.language.languageCode?.identifier ?? VoiceSettings.language
        guard let list = await listVoices(), !list.isEmpty else {
            // No list from the server: its default voice name, if it takes any.
            let saved = VoiceSettings.voiceStudioVoice
            return VoiceStudioAPI.Voice(id: saved.isEmpty ? "alloy" : saved, name: saved, language: nil, gender: nil)
        }
        return VoiceStudioAPI.pick(list, saved: VoiceSettings.voiceStudioVoice,
                                   language: language, gender: VoiceSettings.elevenGender)
    }

    /// Opens VoiceStudio (it serves the voices only while it runs).
    static func openApp() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }
}
#endif
