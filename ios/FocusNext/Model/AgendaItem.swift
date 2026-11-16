import Foundation

/// A calendar event or a reminder, flattened into one value type so the UI
/// and the scheduling logic never touch EventKit objects directly.
struct AgendaItem: Identifiable, Hashable, Codable, Sendable {
    enum Kind: String, Codable, Sendable {
        case event
        case reminder
    }

    struct Tint: Hashable, Codable, Sendable {
        var red: Double
        var green: Double
        var blue: Double

        static let fallback = Tint(red: 0.56, green: 0.83, blue: 0.86)
    }

    let id: String
    let kind: Kind
    var title: String
    /// Event start, or reminder due date. For items without a time of day
    /// (all-day events, date-only reminders) this is the start of that day.
    var date: Date
    /// Event end. Reminders have none.
    var end: Date?
    /// False for all-day events and date-only reminders.
    var hasTime: Bool
    var calendarTitle: String
    var tint: Tint = .fallback
    var location: String?
    var isCompleted: Bool = false

    /// A timed event that is running at `now`.
    func isInProgress(at now: Date) -> Bool {
        guard kind == .event, hasTime, let end else { return false }
        return date <= now && now < end
    }

    /// A timed event that has already finished.
    func isOver(at now: Date) -> Bool {
        guard kind == .event, hasTime, let end else { return false }
        return end <= now
    }

    /// An open reminder whose due moment has passed.
    func isOverdue(at now: Date, calendar: Calendar = .current) -> Bool {
        guard kind == .reminder, !isCompleted else { return false }
        if hasTime { return date < now }
        return date < calendar.startOfDay(for: now)
    }
}
