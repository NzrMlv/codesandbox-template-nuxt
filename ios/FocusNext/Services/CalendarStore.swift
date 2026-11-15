import EventKit
import SwiftUI
import UIKit

/// Reads today's (and tomorrow's) events and reminders from EventKit and keeps
/// them fresh when the underlying Calendar / Reminders data changes.
@MainActor
final class CalendarStore: ObservableObject {
    enum Access {
        /// At least one of Calendar / Reminders has not been asked for yet.
        case needsPrompt
        /// At least one of the two is readable.
        case ready
        /// Both were refused.
        case denied
    }

    @Published private(set) var items: [AgendaItem] = []
    @Published private(set) var eventsStatus = EKEventStore.authorizationStatus(for: .event)
    @Published private(set) var remindersStatus = EKEventStore.authorizationStatus(for: .reminder)
    @Published var errorMessage: String?

    private let store = EKEventStore()

    var canReadEvents: Bool { eventsStatus == .fullAccess }
    var canReadReminders: Bool { remindersStatus == .fullAccess }

    var access: Access {
        if eventsStatus == .notDetermined || remindersStatus == .notDetermined { return .needsPrompt }
        return canReadEvents || canReadReminders ? .ready : .denied
    }

    init() {
        // The store lives as long as the app, so these observers are never removed.
        let names: [Notification.Name] = [.EKEventStoreChanged, .NSCalendarDayChanged]
        for name in names {
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in await self?.refresh() }
            }
        }
    }

    /// Shows the system permission prompts (Calendar first, then Reminders).
    func requestAccess() async {
        if eventsStatus == .notDetermined {
            _ = try? await store.requestFullAccessToEvents()
        }
        if remindersStatus == .notDetermined {
            _ = try? await store.requestFullAccessToReminders()
        }
        await refresh()
    }

    func refresh() async {
        eventsStatus = EKEventStore.authorizationStatus(for: .event)
        remindersStatus = EKEventStore.authorizationStatus(for: .reminder)

        // Today plus tomorrow, so "next" still has an answer late in the evening.
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: .now)
        guard
            let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart),
            let windowEnd = calendar.date(byAdding: .day, value: 2, to: dayStart)
        else { return }

        var result: [AgendaItem] = []
        if canReadEvents {
            result += events(from: dayStart, to: windowEnd)
        }
        if canReadReminders {
            let open = store.predicateForIncompleteReminders(
                withDueDateStarting: nil, ending: windowEnd, calendars: nil)
            let doneToday = store.predicateForCompletedReminders(
                withCompletionDateStarting: dayStart, ending: dayEnd, calendars: nil)
            result += await reminders(matching: open)
            result += await reminders(matching: doneToday)
        }

        // The two reminder queries cannot overlap, but stay safe against duplicate ids.
        var seen = Set<String>()
        items = result.filter { seen.insert($0.id).inserted }
    }

    /// Marks a reminder done (or not done) in Apple Reminders.
    func setCompleted(_ item: AgendaItem, _ completed: Bool) {
        guard item.kind == .reminder,
              let reminder = store.calendarItem(withIdentifier: item.id) as? EKReminder
        else { return }

        reminder.isCompleted = completed
        do {
            try store.save(reminder, commit: true)
            if let index = items.firstIndex(where: { $0.id == item.id }) {
                items[index].isCompleted = completed
            }
        } catch {
            errorMessage = "Couldn't update the reminder: \(error.localizedDescription)"
        }
    }

    // MARK: - Fetching

    private func events(from start: Date, to end: Date) -> [AgendaItem] {
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        return store.events(matching: predicate).compactMap { event -> AgendaItem? in
            guard event.status != .canceled else { return nil }
            let declined = event.attendees?.contains {
                $0.isCurrentUser && $0.participantStatus == .declined
            } ?? false
            guard !declined else { return nil }

            return AgendaItem(
                // Occurrences of a repeating event share an identifier.
                id: "\(event.eventIdentifier ?? UUID().uuidString)@\(event.startDate.timeIntervalSince1970)",
                kind: .event,
                title: Self.title(event.title),
                date: event.startDate,
                end: event.endDate,
                hasTime: !event.isAllDay,
                calendarTitle: event.calendar?.title ?? "",
                tint: Self.tint(event.calendar),
                location: event.location.flatMap { $0.isEmpty ? nil : $0 }
            )
        }
    }

    private func reminders(matching predicate: NSPredicate) async -> [AgendaItem] {
        await withCheckedContinuation { continuation in
            store.fetchReminders(matching: predicate) { reminders in
                let calendar = Calendar.current
                let mapped: [AgendaItem] = (reminders ?? []).compactMap { reminder -> AgendaItem? in
                    // Reminders with no due date are not part of a day plan.
                    guard let due = reminder.dueDateComponents,
                          let date = calendar.date(from: due)
                    else { return nil }
                    let hasTime = due.hour != nil
                    return AgendaItem(
                        id: reminder.calendarItemIdentifier,
                        kind: .reminder,
                        title: Self.title(reminder.title),
                        date: hasTime ? date : calendar.startOfDay(for: date),
                        end: nil,
                        hasTime: hasTime,
                        calendarTitle: reminder.calendar?.title ?? "",
                        tint: Self.tint(reminder.calendar),
                        location: nil,
                        isCompleted: reminder.isCompleted
                    )
                }
                continuation.resume(returning: mapped)
            }
        }
    }

    private nonisolated static func title(_ raw: String?) -> String {
        let trimmed = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled" : trimmed
    }

    private nonisolated static func tint(_ calendar: EKCalendar?) -> AgendaItem.Tint {
        guard let cgColor = calendar?.cgColor else { return .fallback }
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard UIColor(cgColor: cgColor).getRed(&r, green: &g, blue: &b, alpha: &a) else { return .fallback }
        return AgendaItem.Tint(red: Double(r), green: Double(g), blue: Double(b))
    }
}
