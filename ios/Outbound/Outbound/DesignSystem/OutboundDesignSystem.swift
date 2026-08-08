import SwiftUI

enum OutboundSpacing {
    static let compact: CGFloat = 8
    static let standard: CGFloat = 12
    static let section: CGFloat = 20
    static let screen: CGFloat = 20
}

enum OutboundRadius {
    static let control: CGFloat = 14
    static let card: CGFloat = 20
    static let hero: CGFloat = 24
}

enum OutboundPalette {
    static let background = Color(uiColor: .systemGroupedBackground)
    static let surface = Color(uiColor: .secondarySystemGroupedBackground)
    static let primaryText = Color.primary
    static let secondaryText = Color.secondary
    static let companion = Color(red: 0.19, green: 0.37, blue: 0.25)
    static let action = Color(red: 0.89, green: 0.44, blue: 0.29)
}

struct OutboundCard<Content: View>: View {
    enum Style {
        case standard
        case companion
    }

    let style: Style
    let content: Content

    init(style: Style = .standard, @ViewBuilder content: () -> Content) {
        self.style = style
        self.content = content()
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(style == .companion ? 22 : 16)
            .foregroundStyle(style == .companion ? Color.white : OutboundPalette.primaryText)
            .background(backgroundStyle, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                if style == .standard {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.07), lineWidth: 1)
                }
            }
    }

    private var backgroundStyle: AnyShapeStyle {
        switch style {
        case .standard:
            AnyShapeStyle(OutboundPalette.surface)
        case .companion:
            AnyShapeStyle(OutboundPalette.companion.gradient)
        }
    }

    private var cornerRadius: CGFloat {
        style == .companion ? OutboundRadius.hero : OutboundRadius.card
    }
}

struct OutboundPrimaryButton: View {
    let title: String
    var systemImage: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: OutboundSpacing.compact) {
                if let systemImage {
                    Image(systemName: systemImage)
                }
                Text(title)
            }
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: 48)
            .foregroundStyle(.white)
            .background(OutboundPalette.action, in: RoundedRectangle(cornerRadius: OutboundRadius.control, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

struct AIExplanationView: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: OutboundSpacing.compact) {
            Image(systemName: "sparkles")
                .accessibilityHidden(true)
            Text(text)
                .font(.subheadline)
        }
        .foregroundStyle(OutboundPalette.companion)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Companion insight: \(text)")
    }
}

struct WorkoutPhaseItem: Identifiable, Hashable {
    let id: String
    let duration: String
    let title: String
    let weight: CGFloat
}

struct WorkoutPhaseSummary: View {
    let phases: [WorkoutPhaseItem]

    var body: some View {
        HStack(spacing: 1) {
            ForEach(phases) { phase in
                VStack(spacing: 2) {
                    Text(phase.duration)
                        .font(.subheadline.weight(.semibold))
                    Text(phase.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, minHeight: 54)
                .background(Color.primary.opacity(0.045))
                .layoutPriority(Double(phase.weight))
                .accessibilityElement(children: .combine)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: OutboundRadius.control, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: OutboundRadius.control, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        }
    }
}
