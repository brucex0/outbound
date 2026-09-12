import SwiftUI

struct NotificationCenterIcon: View {
    let count: Int

    var body: some View {
        Image(systemName: "bell.fill")
            .frame(width: 30, height: 24)
            .overlay(alignment: .topTrailing) {
                if count > 0 {
                    Text(count > 99 ? "99+" : count.formatted())
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 4)
                        .frame(minWidth: 18, minHeight: 18)
                        .background(Color.red, in: Capsule())
                        .overlay {
                            Capsule().stroke(Color(.systemBackground), lineWidth: 2)
                        }
                        .offset(x: 7, y: -7)
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
            defaultValue: "New items: %d"
        ),
        locale: .autoupdatingCurrent,
        count
    )
}
