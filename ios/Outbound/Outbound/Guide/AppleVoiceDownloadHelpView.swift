import SwiftUI

struct AppleVoiceDownloadHelpView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Label("Open the Settings app", systemImage: "gear")
                    Label("Choose Accessibility", systemImage: "accessibility")
                    Label("Open Read & Speak (or Spoken Content), then Voices", systemImage: "text.bubble")
                    Label("Pick your language and download an Enhanced or Premium voice", systemImage: "arrow.down.circle")
                } header: {
                    Text("On your iPhone")
                } footer: {
                    Text("Apple manages these voice downloads. Plainstride will find the new voice when you return to the app.")
                }
            }
            .navigationTitle("Download a Better Voice")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
