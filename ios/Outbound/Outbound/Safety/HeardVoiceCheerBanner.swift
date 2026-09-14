import SwiftUI

struct HeardVoiceCheerBanner: View {
    let senderDisplayName: String
    let onAcknowledge: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "waveform.circle.fill")
                .font(.title2)
                .foregroundStyle(.orange)

            Text(
                String(
                    format: String(
                        localized: "cheer.runner.heard_from",
                        defaultValue: "%@ cheered you on"
                    ),
                    senderDisplayName
                )
            )
            .font(.subheadline.weight(.semibold))
            .lineLimit(2)
            .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: onAcknowledge) {
                Text(String(localized: "cheer.runner.acknowledge", defaultValue: "❤️ Heard you"))
                    .font(.subheadline.weight(.bold))
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(localized: "cheer.runner.dismiss", defaultValue: "Dismiss cheer"))
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(.white.opacity(0.24))
        }
        .shadow(color: .black.opacity(0.18), radius: 14, y: 6)
        .frame(maxWidth: 420)
        .accessibilityElement(children: .contain)
    }
}
