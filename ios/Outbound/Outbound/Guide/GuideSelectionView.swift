import SwiftUI

struct GuideSelectionView: View {
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject var guideCatalog: GuideCatalogStore
    @State private var previewSynthesizer: GuideSpeechSynthesizer?
    @State private var isPreviewingVoice = false
    @State private var showsVoiceDownloadHelp = false

    var body: some View {
        Form {
            Section(String(localized: "guide.voice.section.title", defaultValue: "Voice")) {
                if downloadedAppleVoices.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Label(String(localized: "guide.voice.add_apple_voice", defaultValue: "Add a more natural Apple voice"), systemImage: "arrow.down.circle")
                            .font(.subheadline.weight(.semibold))
                        Text(String(localized: "guide.voice.add_apple_voice.detail", defaultValue: "Your built-in voices still work. Enhanced and Premium voices can make spoken coaching sound more natural."))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Button(String(localized: "guide.voice.download_help", defaultValue: "How to download a voice")) {
                            showsVoiceDownloadHelp = true
                        }
                    }
                    .padding(.vertical, 4)
                }

                ForEach(GuideGenderPresentation.allCases) { gender in
                    let voices = downloadedAppleVoices(for: gender)
                    if !voices.isEmpty {
                        HStack(spacing: 0) {
                            Text(String(localized: "guide.voice.downloaded.apple", defaultValue: "Downloaded Apple"))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Text(" · ")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Text(gender.displayName)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        ForEach(voices) { voice in
                            voiceButton(voice)
                        }
                    }
                }

                if !downloadedAppleVoicesWithUnspecifiedGender.isEmpty {
                    Text(String(localized: "guide.voice.downloaded.apple", defaultValue: "Downloaded Apple"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    ForEach(downloadedAppleVoicesWithUnspecifiedGender) { voice in
                        voiceButton(voice)
                    }
                }

                Text(String(localized: "guide.voice.other_voices", defaultValue: "Other voices"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                ForEach(otherVoices) { voice in
                    voiceButton(voice)
                }
            }

            Section(String(localized: "guide.tone.section.title", defaultValue: "Coaching tone")) {
                Picker(String(localized: "guide.tone.picker.title", defaultValue: "Coaching tone"), selection: intensityBinding) {
                    ForEach(GuidanceIntensity.allCases) { intensity in
                        Text(intensity.displayName).tag(intensity)
                    }
                }
                .pickerStyle(.segmented)

                Picker(String(localized: "guide.tone.spoken_updates", defaultValue: "Spoken Updates"), selection: nudgeFrequencyBinding) {
                    ForEach(NudgeFrequency.allCases) { frequency in
                        Text(frequency.displayName).tag(frequency)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section(String(localized: "guide.preview.section.title", defaultValue: "Preview")) {
                Button {
                    previewSelectedVoice()
                } label: {
                    Label(
                        isPreviewingVoice ? String(localized: "guide.preview.stop", defaultValue: "Stop Preview") : String(localized: "guide.preview.play", defaultValue: "Play Coaching Preview"),
                        systemImage: isPreviewingVoice ? "stop.fill" : "play.fill"
                    )
                }
            }

            Section {
                Text(String(localized: "guide.tone.frequency.help", defaultValue: "Update frequency controls how often your companion offers spoken nudges and live pace, time, and distance recaps during an activity."))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle(String(localized: "live_guidance.title", defaultValue: "Live Guidance"))
        .onAppear {
            guideCatalog.refreshInstalledVoices()
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            guideCatalog.refreshInstalledVoices()
        }
        .sheet(isPresented: $showsVoiceDownloadHelp) {
            AppleVoiceDownloadHelpView()
        }
        .onDisappear {
            stopVoicePreview()
        }
    }

    private func voiceButton(_ voice: GuideVoice) -> some View {
        Button {
            stopVoicePreview()
            guideCatalog.setVoice(id: voice.id)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "waveform.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.orange)

                VStack(alignment: .leading, spacing: 3) {
                    Text(voice.displayName)
                        .foregroundStyle(.primary)
                    Text(voice.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if guideCatalog.selectedVoice.id == voice.id {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.orange)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func downloadedAppleVoices(for gender: GuideGenderPresentation) -> [GuideVoice] {
        downloadedAppleVoices.filter {
            $0.genderPresentation == gender
        }
    }

    private var downloadedAppleVoices: [GuideVoice] {
        guideCatalog.selectedTemplate.voiceOptions.filter { $0.appleVoiceIdentifier != nil }
    }

    private var downloadedAppleVoicesWithUnspecifiedGender: [GuideVoice] {
        downloadedAppleVoices.filter { $0.genderPresentation == nil }
    }

    private var otherVoices: [GuideVoice] {
        guideCatalog.selectedTemplate.voiceOptions.filter {
            $0.appleVoiceIdentifier == nil
        }
    }

    private func previewSelectedVoice() {
        if isPreviewingVoice {
            stopVoicePreview()
            return
        }

        let synthesizer = previewSynthesizer ?? GuideSpeechSynthesizer()
        synthesizer.eventHandler = { event in
            if case .didFinish = event {
                isPreviewingVoice = false
            }
        }
        previewSynthesizer = synthesizer
        isPreviewingVoice = true
        let voice = guideCatalog.selectedVoice
        synthesizer.speak(
            coachingPreviewText,
            voice: voice,
            speed: 1,
            volume: voice.volume
        )
    }

    private var coachingPreviewText: String {
        switch (AppLanguage.current, guideCatalog.selection.intensity) {
        case (.english, .calm):
            String(localized: "guide.preview.en.calm", defaultValue: "You’re doing well. Relax your shoulders, breathe easily, and let the rhythm come to you.")
        case (.english, .balanced):
            String(localized: "guide.preview.en.balanced", defaultValue: "Nice work. Stay relaxed, keep your steps light, and hold this steady rhythm.")
        case (.english, .driven):
            String(localized: "guide.preview.en.driven", defaultValue: "You’ve got this. Stay tall, quicken your feet, and drive through this next stretch.")
        case (.spanish, .calm):
            "Vas muy bien. Relaja los hombros, respira con calma y deja que llegue el ritmo."
        case (.spanish, .balanced):
            "Buen trabajo. Mantente relajado, pisa ligero y conserva este ritmo constante."
        case (.spanish, .driven):
            "Tú puedes. Mantente erguido, acelera los pies y aprieta en este próximo tramo."
        case (.simplifiedChinese, .calm):
            "跑得很好。放松肩膀，轻松呼吸，让节奏自然形成。"
        case (.simplifiedChinese, .balanced):
            "做得不错。保持放松，脚步轻盈，稳住现在的节奏。"
        case (.simplifiedChinese, .driven):
            "你可以的。挺直身体，加快脚步，全力跑过下一段。"
        }
    }

    private func stopVoicePreview() {
        previewSynthesizer?.stopSpeaking(at: .immediate)
        isPreviewingVoice = false
    }

    private var intensityBinding: Binding<GuidanceIntensity> {
        Binding(
            get: { guideCatalog.selection.intensity },
            set: { guideCatalog.setIntensity($0) }
        )
    }

    private var nudgeFrequencyBinding: Binding<NudgeFrequency> {
        Binding(
            get: { guideCatalog.selection.nudgeFrequency },
            set: { guideCatalog.setNudgeFrequency($0) }
        )
    }
}
