import SwiftUI

struct ActivityRecencyText: View {
    let date: Date
    @Environment(\.locale) private var locale

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            Text(relativeLabel(for: date, relativeTo: context.date))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func relativeLabel(for date: Date, relativeTo referenceDate: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = locale
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: referenceDate)
    }
}
