import SwiftUI

struct NotificationCenterIcon: View {
    let count: Int

    var body: some View {
        Image(systemName: "bell.fill")
            .frame(width: 30, height: 24)
            .overlay(alignment: .topTrailing) {
                if count > 0 {
                    Text(verbatim: count > 9 ? "9+" : String(count))
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 3)
                        .frame(minWidth: 16, minHeight: 16)
                        .background(Color.red, in: Capsule())
                        .overlay {
                            Capsule().stroke(Color(.systemBackground), lineWidth: 1)
                        }
                        .offset(x: 5, y: -7)
                        .accessibilityHidden(true)
                }
            }
    }
}

func notificationCenterAccessibilityValue(count: Int) -> String {
    guard count > 0 else { return "" }
    return String(
        format: String(
            localized: "notification.center.badge.count",
            defaultValue: "Needs your attention: %d"
        ),
        locale: .autoupdatingCurrent,
        count
    )
}
