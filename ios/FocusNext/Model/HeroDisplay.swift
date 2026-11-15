import Foundation

/// Everything the ring and its labels need for one instant in time.
struct HeroDisplay: Equatable {
    var heading: String
    var caption: String
    var value: String
    var detail: String
    var title: String
    /// 0...1, how far along the ring is.
    var progress: Double
    var tint: AgendaItem.Tint
    /// The item the ring is about, if any.
    var item: AgendaItem?

    static func make(
        agenda: Agenda,
        session: FocusSession.Active?,
        now: Date
    ) -> HeroDisplay {
        if let session, session.end > now {
            return HeroDisplay(
                heading: "Focus",
                caption: "Focusing",
                value: Countdown.clock(session.end.timeIntervalSince(now)),
                detail: "until \(time(session.end))",
                title: session.item.title,
                progress: fraction(from: session.start, to: session.end, now: now),
                tint: session.item.tint,
                item: session.item
            )
        }

        switch agenda.hero(at: now) {
        case let .inProgress(item, next):
            let end = item.end ?? now
            let detail: String
            if let next {
                detail = "Next: \(next.title) at \(time(next.date))"
            } else {
                detail = "until \(time(end))"
            }
            return HeroDisplay(
                heading: "Now",
                caption: "Ends in",
                value: Countdown.short(end.timeIntervalSince(now)),
                detail: detail,
                title: item.title,
                progress: fraction(from: item.date, to: end, now: now),
                tint: item.tint,
                item: item
            )

        case let .upcoming(item, since):
            var detail = "at \(time(item.date))"
            if !agenda.calendar.isDate(item.date, inSameDayAs: now) {
                detail = "tomorrow " + detail
            }
            if let end = item.end, end > item.date {
                detail += " for \(Countdown.duration(end.timeIntervalSince(item.date)))"
            }
            return HeroDisplay(
                heading: "Up Next",
                caption: item.kind == .reminder ? "Due in" : "Starts in",
                value: Countdown.short(item.date.timeIntervalSince(now)),
                detail: detail,
                title: item.title,
                progress: fraction(from: since, to: item.date, now: now),
                tint: item.tint,
                item: item
            )

        case let .free(openTasks):
            let detail: String
            switch openTasks {
            case 0: detail = "Nothing else scheduled"
            case 1: detail = "1 open task today"
            default: detail = "\(openTasks) open tasks today"
            }
            return HeroDisplay(
                heading: "Today",
                caption: "You're",
                value: "Free",
                detail: detail,
                title: agenda.openTasks(at: now).first?.title ?? "",
                progress: 0,
                tint: .fallback,
                item: agenda.openTasks(at: now).first
            )
        }
    }

    static func time(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    private static func fraction(from start: Date, to end: Date, now: Date) -> Double {
        let total = end.timeIntervalSince(start)
        guard total > 0 else { return 0 }
        return min(1, max(0, now.timeIntervalSince(start) / total))
    }
}
