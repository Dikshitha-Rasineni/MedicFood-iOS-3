import Foundation

extension Date {
    /// "Today", "Yesterday", or a short date.
    var relativeDayDescription: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(self) { return "Today" }
        if calendar.isDateInYesterday(self) { return "Yesterday" }
        if calendar.isDateInTomorrow(self) { return "Tomorrow" }
        return formatted(date: .abbreviated, time: .omitted)
    }

    /// "2 hours ago" — used for a patient's last activity.
    var timeAgoDescription: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: self, relativeTo: .now)
    }

    var startOfDay: Date { Calendar.current.startOfDay(for: self) }

    func adding(days: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: days, to: self) ?? self
    }
}

extension DateComponents {
    /// Render an hour/minute pair as a localised clock time.
    var clockTimeDescription: String {
        guard let date = Calendar.current.date(from: self) else { return "" }
        return date.formatted(date: .omitted, time: .shortened)
    }
}
