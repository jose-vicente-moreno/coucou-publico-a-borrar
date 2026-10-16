#if !APPSTORE
import SwiftUI

/// Settings → Voice, when the engine is VoiceStudio: address, status, voice, test.
struct VoiceStudioSettingsRow: View {
    @AppStorage("voiceStudioURL") private var baseURL: String = VoiceStudioAPI.defaultBaseURL
    @AppStorage("voiceStudioVoice") private var voiceId: String = ""
    @State private var voices: [VoiceStudioAPI.Voice]?
    @State private var checking = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                TextField(VoiceStudioAPI.defaultBaseURL, text: $baseURL)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 220)
                    .onSubmit { Task { await check() } }
                Button("Check") { Task { await check() } }
                    .disabled(checking)
            }

            HStack(spacing: 6) {
                Circle().fill(statusColor).frame(width: 8, height: 8)
                Text(statusText).font(.system(size: 11)).foregroundColor(.secondary)
                if voices == nil, !checking {
                    Button("Open VoiceStudio") {
                        VoiceStudioTTS.openApp()
                    }
                    .controlSize(.small)
                }
            }

            if let voices, !voices.isEmpty {
                Picker("Voice", selection: $voiceId) {
                    Text("Automatic (answer language)").tag("")
                    ForEach(voices, id: \.id) { voice in
                        Text(label(voice)).tag(voice.id)
                    }
                }
                .frame(maxWidth: 320)
                .onChange(of: voiceId) { _, _ in VoiceStudioTTS.shared.reset() }
            }

            Text("Local open-source voices: VoiceStudio runs on this Mac, no key, nothing leaves it. While it is closed, the Mac voice answers.")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .task { await check() }
    }

    private var statusText: String {
        if checking { return String(localized: "Checking…") }
        guard let voices else { return String(localized: "VoiceStudio isn't answering.") }
        return voices.isEmpty ? String(localized: "Connected (no voice list: its default voice is used).")
                              : String(localized: "Connected · \(voices.count) voices")
    }

    private var statusColor: Color {
        checking ? .yellow : (voices == nil ? .orange : .green)
    }

    private func label(_ voice: VoiceStudioAPI.Voice) -> String {
        let details = [voice.language, voice.gender].compactMap { $0 }.joined(separator: " · ")
        return details.isEmpty ? voice.name : "\(voice.name) — \(details)"
    }

    private func check() async {
        checking = true
        VoiceStudioTTS.shared.reset()
        voices = await VoiceStudioTTS.shared.listVoices(refresh: true)
        checking = false
    }
}
#endif
