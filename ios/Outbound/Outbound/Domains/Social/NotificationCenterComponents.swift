import SwiftUI

struct NotificationCenterIcon: View {
    let count: Int

    var body: some View {
        Image(systemName: "bell.fill")
            .frame(width: 30, height: 24)
            .overlay(alignment: .topTrailing) {
                if count > 0 {
                    Text(verbatim: count > 9 ? "9+" : String(count))
                        .font(.system(size: 7, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 2)
                        .frame(minWidth: 12, minHeight: 12)
                        .background(Color.red, in: Capsule())
                        .overlay {
                            Capsule().stroke(Color(.systemBackground), lineWidth: 1)
                        }
                        .offset(x: 4, y: -4)
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
