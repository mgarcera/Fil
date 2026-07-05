import Foundation

struct FilDayPartition {
    let referenceDate: Date
    let calendar: Calendar

    init(referenceDate: Date = .now, calendar: Calendar = .autoupdatingCurrent) {
        self.referenceDate = referenceDate
        self.calendar = calendar
    }

    var referenceDayStart: Date {
        calendar.startOfDay(for: referenceDate)
    }

    func dayStart(for date: Date) -> Date {
        calendar.startOfDay(for: date)
    }

    func isToday(_ date: Date) -> Bool {
        calendar.isDate(date, inSameDayAs: referenceDate)
    }

    func isYesterday(_ date: Date) -> Bool {
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: referenceDate) else {
            return false
        }

        return calendar.isDate(date, inSameDayAs: yesterday)
    }

    func isTomorrow(_ date: Date) -> Bool {
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: referenceDate) else {
            return false
        }

        return calendar.isDate(date, inSameDayAs: tomorrow)
    }

    func dayHeaderText(for date: Date) -> String {
        if isToday(date) {
            return "Today"
        } else if isYesterday(date) {
            return "Yesterday"
        } else {
            return date.formatted(.dateTime.month(.wide).day().year())
        }
    }

    func relativeLabel(for date: Date) -> String {
        if isToday(date) {
            return "today"
        }
        if isTomorrow(date) {
            return "tomorrow"
        }
        if isYesterday(date) {
            return "yesterday"
        }

        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.dateFormat = "EEEE"
        return formatter.string(from: date).lowercased()
    }
}
