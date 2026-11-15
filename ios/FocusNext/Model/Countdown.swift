import Foundation

/// Compact time strings used on the ring.
enum Countdown {
    /// Time left until something: "9h15", "42m", "30s".
    /// Minutes are rounded up so the value never reads as less time than is left.
    static func short(_ interval: TimeInterval) -> String {
        let seconds = max(0, Int(interval.rounded(.up)))
        if seconds < 60 { return "\(seconds)s" }
        let minutes = (seconds + 59) / 60
        if minutes < 60 { return "\(minutes)m" }
        return "\(minutes / 60)h" + twoDigits(minutes % 60)
    }

    /// A running clock for focus sessions: "24:59", "1:02:03".
    static func clock(_ interval: TimeInterval) -> String {
        let seconds = max(0, Int(interval.rounded(.up)))
        let h = seconds / 3600, m = (seconds % 3600) / 60, s = seconds % 60
        if h > 0 { return "\(h):\(twoDigits(m)):\(twoDigits(s))" }
        return "\(twoDigits(m)):\(twoDigits(s))"
    }

    /// A length of time: "30m", "1h", "1h30".
    static func duration(_ interval: TimeInterval) -> String {
        let minutes = max(0, Int((interval / 60).rounded()))
        if minutes < 60 { return "\(minutes)m" }
        let rest = minutes % 60
        return "\(minutes / 60)h" + (rest == 0 ? "" : twoDigits(rest))
    }

    private static func twoDigits(_ value: Int) -> String {
        value < 10 ? "0\(value)" : "\(value)"
    }
}
