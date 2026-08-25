import SwiftUI
import UIKit

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
                    Label(String(localized: "voice_download.step.open_settings", defaultValue: "Open the Settings app"), systemImage: "gear")
                    Label(String(localized: "voice_download.step.accessibility", defaultValue: "Choose Accessibility"), systemImage: "accessibility")
                    Label(String(localized: "voice_download.step.voices", defaultValue: "Open Read & Speak (or Spoken Content), then Voices"), systemImage: "text.bubble")
                    Label(String(localized: "voice_download.step.download", defaultValue: "Pick your language and download an Enhanced or Premium voice"), systemImage: "arrow.down.circle")
                } header: {
                    Text(String(localized: "voice_download.section.iphone", defaultValue: "On your iPhone"))
                } footer: {
                    Text(String(localized: "voice_download.footer", defaultValue: "Apple manages these voice downloads. Plainstride will find the new voice when you return to the app."))
                }

                Section {
                    Button {
                        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                        UIApplication.shared.open(url)
                    } label: {
                        Label(String(localized: "voice_download.open_settings", defaultValue: "Go to Settings"), systemImage: "arrow.up.forward.app")
                    }
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
}
