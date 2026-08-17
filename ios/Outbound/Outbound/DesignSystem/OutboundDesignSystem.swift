import SwiftUI

enum OutboundTheme: String, CaseIterable, Codable, Identifiable {
    case indigo
    case ocean
    case forest
    case rose
    case victoryGold
    case aurora
    case electricLime
    case neonPulse

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .indigo: "Indigo"
        case .ocean: "Ocean"
        case .forest: "Forest"
        case .rose: "Rose"
        case .electricLime: "Electric Lime"
        case .neonPulse: "Neon Pulse"
        case .aurora: "Aurora"
        case .victoryGold: "Victory Gold"
        }
    }

    var accentColor: Color {
        switch self {
        case .indigo: adaptive(0.28, 0.25, 0.78, dark: 0.52, 0.48, 1.00)
        case .ocean: adaptive(0.03, 0.49, 0.75, dark: 0.22, 0.68, 0.95)
        case .forest: adaptive(0.07, 0.51, 0.35, dark: 0.24, 0.72, 0.49)
        case .rose: adaptive(0.78, 0.20, 0.43, dark: 1.00, 0.39, 0.61)
        case .electricLime: adaptive(0.42, 0.72, 0.04, dark: 0.65, 0.95, 0.18)
        case .neonPulse: adaptive(0.84, 0.08, 0.68, dark: 1.00, 0.25, 0.83)
        case .aurora: adaptive(0.05, 0.67, 0.67, dark: 0.23, 0.88, 0.81)
        case .victoryGold: adaptive(0.82, 0.51, 0.00, dark: 1.00, 0.72, 0.13)
        }
    }

    var secondaryColor: Color {
        switch self {
        case .indigo: adaptive(0.50, 0.38, 0.92, dark: 0.70, 0.62, 1.00)
        case .ocean: adaptive(0.00, 0.67, 0.70, dark: 0.18, 0.84, 0.88)
        case .forest: adaptive(0.37, 0.66, 0.18, dark: 0.56, 0.84, 0.34)
        case .rose: adaptive(0.94, 0.43, 0.48, dark: 1.00, 0.57, 0.64)
        case .electricLime: adaptive(0.03, 0.62, 0.39, dark: 0.18, 0.82, 0.54)
        case .neonPulse: adaptive(0.40, 0.18, 0.94, dark: 0.58, 0.40, 1.00)
        case .aurora: adaptive(0.64, 0.23, 0.87, dark: 0.77, 0.44, 1.00)
        case .victoryGold: adaptive(1.00, 0.77, 0.12, dark: 1.00, 0.84, 0.35)
        }
    }

    var actionColor: Color {
        switch self {
        case .indigo: adaptive(0.12, 0.58, 0.52, dark: 0.23, 0.76, 0.68)
        case .ocean: adaptive(0.02, 0.43, 0.70, dark: 0.15, 0.61, 0.90)
        case .forest: adaptive(0.04, 0.43, 0.29, dark: 0.18, 0.63, 0.41)
        case .rose: adaptive(0.68, 0.13, 0.35, dark: 0.89, 0.28, 0.49)
        case .electricLime: adaptive(0.02, 0.45, 0.27, dark: 0.12, 0.65, 0.38)
        case .neonPulse: adaptive(0.53, 0.10, 0.78, dark: 0.71, 0.26, 0.96)
        case .aurora: adaptive(0.04, 0.48, 0.59, dark: 0.15, 0.67, 0.75)
        case .victoryGold: adaptive(0.55, 0.32, 0.00, dark: 0.76, 0.48, 0.03)
        }
    }

    var heroGradient: LinearGradient {
        LinearGradient(
            colors: heroColors,
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    var glowColor: Color { secondaryColor.opacity(0.34) }

    var heroForegroundColor: Color {
        switch self {
        case .electricLime, .victoryGold:
            adaptive(0.16, 0.10, 0.01, dark: 0.13, 0.08, 0.00)
        default:
            .white
        }
    }

    private var heroColors: [Color] {
        switch self {
        case .indigo: [adaptive(0.18, 0.16, 0.58, dark: 0.22, 0.19, 0.52), accentColor, secondaryColor]
        case .ocean: [adaptive(0.01, 0.30, 0.61, dark: 0.02, 0.24, 0.48), accentColor, secondaryColor]
        case .forest: [adaptive(0.03, 0.31, 0.24, dark: 0.03, 0.26, 0.19), accentColor, secondaryColor]
        case .rose: [adaptive(0.57, 0.10, 0.32, dark: 0.46, 0.07, 0.25), accentColor, secondaryColor]
        case .electricLime: [adaptive(0.75, 0.94, 0.18, dark: 0.59, 0.79, 0.10), accentColor, secondaryColor]
        case .neonPulse: [adaptive(1.00, 0.18, 0.70, dark: 0.84, 0.09, 0.60), accentColor, secondaryColor]
        case .aurora: [secondaryColor, adaptive(0.04, 0.72, 0.70, dark: 0.06, 0.61, 0.62), adaptive(0.91, 0.35, 0.69, dark: 0.77, 0.24, 0.59)]
        case .victoryGold: [adaptive(1.00, 0.94, 0.60, dark: 0.91, 0.70, 0.18), secondaryColor, adaptive(0.91, 0.55, 0.00, dark: 0.73, 0.41, 0.00)]
        }
    }

    private func adaptive(
        _ lightRed: Double, _ lightGreen: Double, _ lightBlue: Double,
        dark darkRed: Double, _ darkGreen: Double, _ darkBlue: Double
    ) -> Color {
        Color(uiColor: UIColor { traits in
            let values = traits.userInterfaceStyle == .dark
                ? (darkRed, darkGreen, darkBlue)
                : (lightRed, lightGreen, lightBlue)
            return UIColor(red: values.0, green: values.1, blue: values.2, alpha: 1)
        })
    }

    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        if value == "sunset" || value == "solarFlare" {
            self = .victoryGold
        } else if let theme = Self(rawValue: value) {
            self = theme
        } else {
            self = .indigo
        }
    }
}

private struct OutboundThemeKey: EnvironmentKey {
    static let defaultValue = OutboundTheme.indigo
}

extension EnvironmentValues {
    var outboundTheme: OutboundTheme {
        get { self[OutboundThemeKey.self] }
        set { self[OutboundThemeKey.self] = newValue }
    }
}

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
    static let background = Color(uiColor: .systemBackground)
    static let surface = Color(uiColor: .secondarySystemBackground)
    static let primaryText = Color.primary
    static let secondaryText = Color.secondary
    static var companion: Color { currentTheme.accentColor }
    static var action: Color { currentTheme.actionColor }
    static var heroGradient: LinearGradient { currentTheme.heroGradient }

    private static var currentTheme: OutboundTheme {
        guard let rawValue = UserDefaults.standard.string(forKey: GuideCatalogStore.themeKey),
              let theme = OutboundTheme(rawValue: rawValue) else { return .indigo }
        return theme
    }
}

struct OutboundCard<Content: View>: View {
    @Environment(\.outboundTheme) private var theme
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
            .foregroundStyle(style == .companion ? theme.heroForegroundColor : OutboundPalette.primaryText)
            .background(backgroundStyle, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .shadow(
                color: style == .standard ? Color.black.opacity(0.035) : theme.glowColor,
                radius: style == .standard ? 12 : 18,
                y: 5
            )
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
            AnyShapeStyle(theme.heroGradient)
        }
    }

    private var cornerRadius: CGFloat {
        style == .companion ? OutboundRadius.hero : OutboundRadius.card
    }
}

struct OutboundPrimaryButton: View {
    @Environment(\.outboundTheme) private var theme
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
            .background(theme.actionColor, in: RoundedRectangle(cornerRadius: OutboundRadius.control, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

struct AIExplanationView: View {
    @Environment(\.outboundTheme) private var theme
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: OutboundSpacing.compact) {
            Image(systemName: "sparkles")
                .accessibilityHidden(true)
            Text(text)
                .font(.subheadline)
        }
        .foregroundStyle(theme.accentColor)
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
