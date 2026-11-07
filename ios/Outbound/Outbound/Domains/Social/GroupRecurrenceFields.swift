import SwiftUI

struct GroupRecurrenceFields: View {
    @Binding var repeats: Bool
    @Binding var intervalWeeks: Int
    @Binding var weekdays: Set<Int>
    @Binding var hasEnd: Bool
    @Binding var endDate: Date
    let firstDate: Date
    let timeZone: TimeZone

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }

    var body: some View {
        Section {
            Toggle(String(localized: "Repeat weekly", table: "GroupRecurrence"), isOn: $repeats)
                .accessibilityIdentifier("group.activity.repeat")
            if repeats {
                Picker(String(localized: "Repeat every", table: "GroupRecurrence"), selection: $intervalWeeks) {
                    ForEach(1...4, id: \.self) { interval in
                        Text(groupRecurrenceIntervalLabel(interval)).tag(interval)
                    }
                }
                .accessibilityIdentifier("group.activity.interval")
                ForEach(1...7, id: \.self) { day in
                    Toggle(calendar.weekdaySymbols[day % 7], isOn: Binding(
                        get: { weekdays.contains(day) },
                        set: { selected in if selected { weekdays.insert(day) } else { weekdays.remove(day) } }
                    ))
                    .accessibilityIdentifier("group.activity.weekday.\(day)")
                }
                LabeledContent(String(localized: "Time zone", table: "GroupRecurrence"), value: timeZone.identifier)
                Toggle(String(localized: "End on a date", table: "GroupRecurrence"), isOn: $hasEnd)
                    .accessibilityIdentifier("group.activity.has_end")
                if hasEnd {
                    DatePicker(String(localized: "Last repeat date", table: "GroupRecurrence"), selection: $endDate, in: calendar.startOfDay(for: firstDate)..., displayedComponents: .date)
                        .environment(\.timeZone, timeZone)
                }
            }
        } header: {
            Text(String(localized: "Repeats", table: "GroupRecurrence"))
        }
        .onChange(of: firstDate) { _, date in
            if repeats { weekdays.insert(((calendar.component(.weekday, from: date) + 5) % 7) + 1) }
            if endDate < date { endDate = date }
        }
    }
}

func groupRecurrenceIntervalLabel(_ interval: Int) -> String {
    switch interval {
    case 2: return String(localized: "Every 2 weeks", table: "GroupRecurrence")
    case 3: return String(localized: "Every 3 weeks", table: "GroupRecurrence")
    case 4: return String(localized: "Every 4 weeks", table: "GroupRecurrence")
    default: return String(localized: "Every week", table: "GroupRecurrence")
    }
}

func groupRecurrenceSummary(_ recurrence: ActivityEventRecurrenceDTO) -> String {
    let names = recurrence.weekdays.filter { (1...7).contains($0) }.map { Calendar.current.shortWeekdaySymbols[$0 % 7] }
    return [groupRecurrenceIntervalLabel(recurrence.intervalWeeks), names.formatted(.list(type: .and)), recurrence.timeZone].joined(separator: " · ")
}
