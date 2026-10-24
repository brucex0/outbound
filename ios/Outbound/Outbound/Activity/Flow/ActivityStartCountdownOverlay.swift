import SwiftUI

enum ActivityStartCountdownStep: CaseIterable, Equatable {
    case three
    case two
    case one
    case go

    static let sequence: [ActivityStartCountdownStep] = [.three, .two, .one, .go]

    var displayText: String {
        switch self {
        case .three:
            return "3"
        case .two:
            return "2"
        case .one:
            return "1"
        case .go:
            return String(localized: "record.countdown.go", defaultValue: "Go")
        }
    }

    var spokenText: String {
        switch self {
        case .three:
            return "3"
        case .two:
            return "2"
        case .one:
            return "1"
        case .go:
            return String(localized: "record.countdown.go", defaultValue: "Go")
        }
    }

    var accessibilityText: String {
        switch self {
        case .three:
            return "3"
        case .two:
            return "2"
        case .one:
            return "1"
        case .go:
            return String(localized: "record.countdown.go", defaultValue: "Go")
        }
    }

    var durationNanoseconds: UInt64 {
        switch self {
        case .three, .two, .one:
            return 1_000_000_000
        case .go:
            return 420_000_000
        }
    }

    var progress: CGFloat {
        guard let index = Self.sequence.firstIndex(of: self) else { return 0 }
        return CGFloat(index + 1) / CGFloat(Self.sequence.count)
    }
}

struct ActivityStartCountdownOverlay: View {
    let step: ActivityStartCountdownStep
    let reduceMotion: Bool
    let signalQuality: LocationSignalQuality
    var companionType: ActivityCompanionType? = nil

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.black.opacity(0.42))
                .ignoresSafeArea()

            VStack(spacing: 20) {
                ZStack {
                    Circle()
                        .stroke(.white.opacity(0.2), lineWidth: 8)
                    Circle()
                        .trim(from: 0, to: step.progress)
                        .stroke(
                            Color.orange,
                            style: StrokeStyle(lineWidth: 8, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))

                    Text(step.displayText)
                        .font(.system(size: step == .go ? 76 : 118, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .minimumScaleFactor(0.72)
                        .lineLimit(1)
                        .contentTransition(reduceMotion ? .identity : .numericText())
                        .id(step)
                        .transition(reduceMotion ? .opacity : .scale(scale: 0.86).combined(with: .opacity))
                }
                .frame(width: 188, height: 188)
                .shadow(color: .black.opacity(0.26), radius: 20, y: 8)

                Text("Plainstride")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.86))
                    .lineLimit(1)

                if let companionType {
                    Text(companionType.displayName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.9))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(.black.opacity(0.28), in: Capsule())
                }

                Label(gpsStatusText, systemImage: gpsStatusIcon)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(gpsStatusColor)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(.black.opacity(0.28), in: Capsule())
            }
            .padding(.horizontal, 28)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(step.accessibilityText)
            .accessibilityValue(gpsStatusText)
        }
        .allowsHitTesting(true)
        .animation(.easeInOut(duration: reduceMotion ? 0.12 : 0.24), value: step)
    }

    private var gpsStatusText: String {
        switch signalQuality {
        case .excellent, .good:
            String(localized: "record.gps.ready", defaultValue: "GPS ready")
        case .fair:
            String(localized: "record.gps.improving", defaultValue: "Improving GPS signal")
        case .poor, .unavailable:
            String(localized: "record.gps.acquiring", defaultValue: "Acquiring GPS")
        case .reduced:
            String(localized: "record.gps.precise_off", defaultValue: "Precise Location is off")
        }
    }

    private var gpsStatusIcon: String {
        switch signalQuality {
        case .excellent, .good: "location.fill"
        case .fair: "location"
        case .poor, .unavailable: "location.slash"
        case .reduced: "location.circle"
        }
    }

    private var gpsStatusColor: Color {
        switch signalQuality {
        case .excellent, .good: .green
        case .fair: .yellow
        case .poor, .unavailable, .reduced: .orange
        }
    }
}
