import SwiftUI

struct AppleVoiceDownloadHelpView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(String(localized: "voice_download.explanation", defaultValue: "Plainstride uses Apple voices for spoken coaching. Enhanced or Premium voices sound more natural than the built-in Standard voice."))
                        .foregroundStyle(.secondary)
                }

                Section {
                    voiceDownloadStep(1, String(localized: "voice_download.step.open_settings", defaultValue: "Leave Plainstride and open the Settings app"))
                    voiceDownloadStep(2, String(localized: "voice_download.step.accessibility", defaultValue: "Choose Accessibility"))
                    voiceDownloadStep(3, String(localized: "voice_download.step.voices", defaultValue: "Open Read & Speak (or Spoken Content), then Voices"))
                    voiceDownloadStep(4, String(localized: "voice_download.step.download", defaultValue: "Pick your language and download an Enhanced or Premium voice"))
                } header: {
                    Text(String(localized: "voice_download.section.iphone", defaultValue: "On your iPhone"))
                } footer: {
                    Text(String(localized: "voice_download.footer", defaultValue: "Apple manages these voice downloads. Plainstride will find the new voice when you return to the app."))
                }
            }
            .navigationTitle(String(localized: "voice_download.title", defaultValue: "Download a Better Voice"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "common.done", defaultValue: "Done")) { dismiss() }
                }
            }
        }
    }

    private func voiceDownloadStep(_ number: Int, _ instruction: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(number, format: .number)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 20, alignment: .trailing)

            Text(instruction)
        }
    }
}
