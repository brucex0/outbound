import SwiftUI

struct GuideSelectionView: View {
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject var guideCatalog: GuideCatalogStore
    @State private var previewSynthesizer: GuideSpeechSynthesizer?
    @State private var previewingVoiceID: String?
    @State private var showsVoiceDownloadHelp = false
    @State private var pendingStandardVoice: GuideVoice?

    var body: some View {
        Form {
            if guideCatalog.requiresVoiceSelection {
                Section {
                    Label(
                        voiceRequirementTitle,
                        systemImage: "waveform.badge.exclamationmark"
                    )
                    .font(.headline)
                    Text(voiceRequirementDetail)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Section(String(localized: "guide.voice.section.title", defaultValue: "Voice")) {
                if compatibleDownloadedAppleVoices.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Label(String(localized: "guide.voice.add_apple_voice", defaultValue: "Add a more natural Apple voice"), systemImage: "arrow.down.circle")
                            .font(.subheadline.weight(.semibold))
                        Text(String(localized: "guide.voice.add_apple_voice.detail", defaultValue: "No Premium or Enhanced voice is installed. The available Standard voice may sound noticeably robotic or poor."))
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

                Text(String(localized: "guide.voice.standard.section", defaultValue: "Standard fallback"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                ForEach(standardVoices) { voice in
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
        .alert(
            String(localized: "guide.voice.standard.warning.title", defaultValue: "Use a lower-quality voice?"),
            isPresented: Binding(
                get: { pendingStandardVoice != nil },
                set: { if !$0 { pendingStandardVoice = nil } }
            ),
            presenting: pendingStandardVoice
        ) { voice in
            Button(String(localized: "guide.voice.standard.warning.use", defaultValue: "Use Standard Voice")) {
                guideCatalog.setVoice(id: voice.id)
                pendingStandardVoice = nil
            }
            Button(String(localized: "Cancel"), role: .cancel) {
                pendingStandardVoice = nil
            }
        } message: { _ in
            Text(String(localized: "guide.voice.standard.warning.message", defaultValue: "Standard system voices can sound robotic or poor. Download an Apple Premium or Enhanced voice for more natural coaching."))
        }
        .onDisappear {
            stopVoicePreview()
        }
    }

    private func voiceButton(_ voice: GuideVoice) -> some View {
        HStack(spacing: 12) {
            Button {
                previewVoice(voice)
            } label: {
                Image(systemName: previewingVoiceID == voice.id ? "waveform.circle.fill" : "play.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.orange)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
                previewingVoiceID == voice.id
                    ? String(localized: "guide.preview.stop", defaultValue: "Stop Preview")
                    : String(localized: "guide.preview.voice", defaultValue: "Preview Voice")
            )
            .accessibilityHint(voice.displayName)

            Button {
                stopVoicePreview()
                if voice.isStandardQuality, guideCatalog.selectedVoice.id != voice.id {
                    pendingStandardVoice = voice
                } else {
                    guideCatalog.setVoice(id: voice.id)
                }
            } label: {
                HStack(spacing: 12) {
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
    }

    private func previewVoice(_ voice: GuideVoice) {
        if previewingVoiceID == voice.id {
            stopVoicePreview()
            return
        }

        stopVoicePreview()
        let synthesizer = previewSynthesizer ?? GuideSpeechSynthesizer()
        synthesizer.eventHandler = { event in
            if case .didFinish = event {
                previewingVoiceID = nil
            }
        }
        previewSynthesizer = synthesizer
        previewingVoiceID = voice.id
        synthesizer.speak(
            coachingPreviewText(for: voice),
            voice: voice,
            rate: voice.rate,
            volume: voice.volume
        )
    }

    private func downloadedAppleVoices(for gender: GuideGenderPresentation) -> [GuideVoice] {
        downloadedAppleVoices.filter {
            $0.genderPresentation == gender
        }
    }

    private var downloadedAppleVoices: [GuideVoice] {
        guideCatalog.selectedTemplate.voiceOptions.filter {
            $0.appleVoiceIdentifier != nil && !$0.isStandardQuality
        }
    }

    private var voiceRequirementTitle: String {
        switch guideCatalog.voiceSelectionRequirementReason {
        case .appLanguageChanged:
            String(localized: "guide.voice.language_changed.title", defaultValue: "Choose a voice for this language")
        case .selectedVoiceUnavailable:
            String(localized: "guide.voice.unavailable.title", defaultValue: "Your selected voice is unavailable")
        case .initialSelection, .none:
            String(localized: "guide.voice.required.title", defaultValue: "Choose a voice for spoken guidance")
        }
    }

    private var voiceRequirementDetail: String {
        switch guideCatalog.voiceSelectionRequirementReason {
        case .appLanguageChanged:
            String(localized: "guide.voice.language_changed.detail", defaultValue: "The app language changed, so your previous voice may pronounce coaching incorrectly. Spoken guidance is paused until you choose and preview a compatible voice.")
        case .selectedVoiceUnavailable:
            String(localized: "guide.voice.unavailable.detail", defaultValue: "The voice you chose is no longer installed or compatible with the app language. Spoken guidance is paused until you choose another voice.")
        case .initialSelection, .none:
            String(localized: "guide.voice.required.detail", defaultValue: "Choose and preview a compatible voice before spoken guidance begins. Standard voices require an additional quality warning.")
        }
    }

    private var compatibleDownloadedAppleVoices: [GuideVoice] { downloadedAppleVoices }

    private var downloadedAppleVoicesWithUnspecifiedGender: [GuideVoice] {
        downloadedAppleVoices.filter { $0.genderPresentation == nil }
    }

    private var standardVoices: [GuideVoice] {
        guideCatalog.selectedTemplate.voiceOptions.filter {
            $0.isStandardQuality
        }
    }

    private func coachingPreviewText(for voice: GuideVoice) -> String {
        let voiceLanguage = AppLanguage.language(matching: voice.locale)
        return switch (voiceLanguage, guideCatalog.selection.intensity) {
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
        previewingVoiceID = nil
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
