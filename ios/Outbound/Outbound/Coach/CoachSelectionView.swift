import SwiftUI

struct CoachSelectionView: View {
    @EnvironmentObject var coachCatalog: CoachCatalogStore

    var body: some View {
        Form {
            Section("Selected Coach") {
                CoachTemplateSummaryView(persona: coachCatalog.selectedPersona)
            }

            ForEach(SportType.allCases) { sport in
                Section(sport.displayName) {
                    ForEach(coachCatalog.templates(for: sport)) { template in
                        CoachTemplateButton(
                            template: template,
                            isSelected: coachCatalog.selectedTemplate.id == template.id,
                            selectedFace: coachCatalog.selectedFace
                        ) {
                            coachCatalog.select(template)
                        }
                    }
                }
            }

            Section("Customize") {
                Picker("Voice", selection: voiceBinding) {
                    ForEach(coachCatalog.selectedTemplate.voiceOptions) { voice in
                        Text(voice.displayName).tag(voice.id)
                    }
                }

                Picker("Face", selection: faceBinding) {
                    ForEach(coachCatalog.selectedTemplate.faceOptions) { face in
                        Text(face.displayName).tag(face.id)
                    }
                }

                Picker("Style", selection: intensityBinding) {
                    ForEach(CoachingIntensity.allCases) { intensity in
                        Text(intensity.displayName).tag(intensity)
                    }
                }
                .pickerStyle(.segmented)

                Picker("Coach Updates", selection: nudgeFrequencyBinding) {
                    ForEach(NudgeFrequency.allCases) { frequency in
                        Text(frequency.displayName).tag(frequency)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section("Sample Nudges") {
                ForEach(coachCatalog.selectedTemplate.sampleNudges, id: \.self) { nudge in
                    Text(nudge)
                        .font(.subheadline)
                }
            }

            Section {
                Text("Coach update frequency controls how often spoken AI nudges and live pace, time, and distance recaps play during an activity.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Coach")
    }

    private var voiceBinding: Binding<String> {
        Binding(
            get: { coachCatalog.selectedVoice.id },
            set: { coachCatalog.setVoice(id: $0) }
        )
    }

    private var faceBinding: Binding<String> {
        Binding(
            get: { coachCatalog.selectedFace.id },
            set: { coachCatalog.setFace(id: $0) }
        )
    }

    private var intensityBinding: Binding<CoachingIntensity> {
        Binding(
            get: { coachCatalog.selection.intensity },
            set: { coachCatalog.setIntensity($0) }
        )
    }

    private var nudgeFrequencyBinding: Binding<NudgeFrequency> {
        Binding(
            get: { coachCatalog.selection.nudgeFrequency },
            set: { coachCatalog.setNudgeFrequency($0) }
        )
    }
}

struct CoachTemplateSummaryView: View {
    let persona: CoachPersona

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            CoachAvatarView(face: persona.face, size: 58)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Label(persona.template.sport.displayName, systemImage: persona.template.sport.systemImage)
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                    Text(persona.template.genderPresentation.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text(persona.template.displayName)
                    .font(.headline)

                Text(persona.template.tagline)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                HStack(spacing: 10) {
                    CoachPreferencePill(title: persona.voice.displayName, icon: "speaker.wave.2.fill")
                    CoachPreferencePill(title: persona.intensity.displayName, icon: "dial.medium.fill")
                    CoachPreferencePill(title: persona.nudgeFrequency.displayName, icon: "timer")
                }
            }
        }
        .padding(.vertical, 4)
    }
}

struct CoachAvatarView: View {
    let face: CoachFace
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .fill(face.displayColor.gradient)
            Image(systemName: face.symbolName)
                .font(.system(size: max(18, size * 0.42), weight: .semibold))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
        .accessibilityLabel(face.displayName)
    }
}

private struct CoachTemplateButton: View {
    let template: CoachTemplate
    let isSelected: Bool
    let selectedFace: CoachFace
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                CoachAvatarView(
                    face: isSelected ? selectedFace : template.defaultFace,
                    size: 46
                )

                VStack(alignment: .leading, spacing: 4) {
                    Text(template.displayName)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(template.personality.capitalized)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(template.tagline)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.orange)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

private struct CoachPreferencePill: View {
    let title: String
    let icon: String

    var body: some View {
        Label(title, systemImage: icon)
            .font(.caption2.bold())
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color(.tertiarySystemFill))
            .clipShape(Capsule())
    }
}

private extension CoachFace {
    var displayColor: Color {
        switch colorName {
        case "blue": .blue
        case "cyan": .cyan
        case "gray": .gray
        case "green": .green
        case "pink": .pink
        case "purple": .purple
        case "red": .red
        case "teal": .teal
        case "yellow": .yellow
        default: .orange
        }
    }
}
