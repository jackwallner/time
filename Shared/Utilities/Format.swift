import Foundation

enum Format {
    /// "8:15" or "8:15 AM" per the user's locale.
    static func time(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    /// "45 min", "1 hr", "1 hr 8 min".
    static func duration(minutes: Int) -> String {
        let hours = minutes / 60
        let rest = minutes % 60
        if hours == 0 { return "\(rest) min" }
        if rest == 0 { return "\(hours) hr" }
        return "\(hours) hr \(rest) min"
    }

    /// Whole minutes from seconds, rounded to nearest, at least 1 once started.
    static func minutes(fromSeconds seconds: TimeInterval) -> Int {
        max(seconds > 0 ? 1 : 0, Int((seconds / 60).rounded()))
    }

    /// "Today", "Tomorrow", or the weekday name.
    static func day(_ date: Date, now: Date = .now, calendar: Calendar = .current) -> String {
        if calendar.isDate(date, inSameDayAs: now) { return "Today" }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now),
           calendar.isDate(date, inSameDayAs: tomorrow) {
            return "Tomorrow"
        }
        return date.formatted(.dateTime.weekday(.wide))
    }

    /// "in 42 min", "in 3 hr 5 min", "now".
    static func relative(to date: Date, now: Date = .now) -> String {
        let minutes = Int((date.timeIntervalSince(now) / 60).rounded(.up))
        if minutes <= 0 { return "now" }
        return "in \(duration(minutes: minutes))"
    }

    /// "2 min early", "On time", "6 min late".
    static func lateness(seconds: TimeInterval) -> String {
        if seconds <= 60, seconds >= -60 { return "On time" }
        let minutes = Int((abs(seconds) / 60).rounded())
        return seconds < 0 ? "\(minutes) min early" : "\(minutes) min late"
    }

    /// "Weekdays", "Every day", "Weekends", or "Mon, Wed, Fri".
    static func weekdays(_ days: Set<Int>, calendar: Calendar = .current) -> String {
        if days.count == 7 { return "Every day" }
        if days == [2, 3, 4, 5, 6] { return "Weekdays" }
        if days == [1, 7] { return "Weekends" }
        if days.isEmpty { return "No days set" }
        let symbols = calendar.shortWeekdaySymbols
        let ordered = orderedWeekdays(calendar: calendar).filter(days.contains)
        return ordered.map { symbols[$0 - 1] }.joined(separator: ", ")
    }

    /// Weekday numbers in the locale's order, starting from its first weekday.
    static func orderedWeekdays(calendar: Calendar = .current) -> [Int] {
        (0..<7).map { (calendar.firstWeekday - 1 + $0) % 7 + 1 }
    }

    /// "1.5×" style, trimmed.
    static func multiplier(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        if rounded == rounded.rounded() { return "\(Int(rounded))×" }
        return String(format: "%.1f×", rounded)
    }

    /// "50% longer than you guess" style.
    static func paceSentence(_ pace: Double) -> String {
        let percent = Int(((pace - 1) * 100).rounded())
        if abs(percent) < 5 { return "about as long as you guess" }
        if percent > 0 { return "\(percent)% longer than you guess" }
        return "\(-percent)% less than you guess"
    }
}
