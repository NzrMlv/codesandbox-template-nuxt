import Foundation

/// Pure scheduling logic over a list of agenda items: what is happening now,
/// what comes next, and how today's list is grouped.
struct Agenda {
    /// What the big ring at the top of the screen is about.
    enum Hero: Equatable {
        /// A timed event is running right now.
        case inProgress(AgendaItem, next: AgendaItem?)
        /// Nothing is running; this is the next timed item. `since` is when
        /// the current gap began (end of the previous event, or midnight).
        case upcoming(AgendaItem, since: Date)
        /// Nothing timed is left in the fetched window.
        case free(openTasks: Int)
    }

    struct Day: Equatable {
        var allDay: [AgendaItem] = []
        /// Timed events and timed reminders that belong to today, by time.
        var timeline: [AgendaItem] = []
        /// Reminders without a time, plus anything overdue from earlier days.
        var tasks: [AgendaItem] = []

        var isEmpty: Bool { allDay.isEmpty && timeline.isEmpty && tasks.isEmpty }
    }

    var items: [AgendaItem]
    var calendar: Calendar = .current

    /// The running timed event. If several overlap, the one that started last.
    func current(at now: Date) -> AgendaItem? {
        items
            .filter { $0.isInProgress(at: now) }
            .max { $0.date < $1.date }
    }

    /// The earliest timed, open item that starts after `now`.
    func next(at now: Date) -> AgendaItem? {
        items
            .filter { $0.hasTime && !$0.isCompleted && $0.date > now }
            .min { ($0.date, $0.title) < ($1.date, $1.title) }
    }

    func hero(at now: Date) -> Hero {
        let upcoming = next(at: now)
        if let running = current(at: now) {
            return .inProgress(running, next: upcoming)
        }
        if let upcoming {
            let dayStart = calendar.startOfDay(for: now)
            let lastEnd = items
                .filter { $0.isOver(at: now) }
                .compactMap(\.end)
                .max()
            return .upcoming(upcoming, since: max(lastEnd ?? dayStart, dayStart))
        }
        return .free(openTasks: openTasks(at: now).count)
    }

    /// Open reminders that are due today or overdue.
    func openTasks(at now: Date) -> [AgendaItem] {
        let day = day(at: now)
        return (day.timeline + day.tasks).filter { $0.kind == .reminder && !$0.isCompleted }
    }

    /// Everything planned for the day containing `now`.
    func day(at now: Date) -> Day {
        let dayStart = calendar.startOfDay(for: now)
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { return Day() }

        var result = Day()
        for item in items {
            switch item.kind {
            case .event:
                let end = item.end ?? item.date
                // Overlaps today? (An event ending exactly at midnight does not.)
                guard item.date < dayEnd, end > dayStart || item.date >= dayStart else { continue }
                if item.hasTime {
                    result.timeline.append(item)
                } else {
                    result.allDay.append(item)
                }
            case .reminder:
                guard item.date < dayEnd else { continue }
                if item.hasTime, item.date >= dayStart {
                    result.timeline.append(item)
                } else {
                    result.tasks.append(item)
                }
            }
        }

        result.allDay.sort { $0.title < $1.title }
        result.timeline.sort { ($0.date, $0.title) < ($1.date, $1.title) }
        // Open tasks first, oldest due date first; completed ones sink.
        result.tasks.sort {
            ($0.isCompleted ? 1 : 0, $0.date, $0.title) < ($1.isCompleted ? 1 : 0, $1.date, $1.title)
        }
        return result
    }
}
