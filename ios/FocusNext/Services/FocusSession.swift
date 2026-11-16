import SwiftUI
import UIKit
import UserNotifications

/// A single running focus timer attached to an agenda item.
@MainActor
final class FocusSession: ObservableObject {
    struct Active: Codable, Equatable {
        var item: AgendaItem
        var start: Date
        var end: Date
    }

    @Published private(set) var active: Active?

    private var timer: Task<Void, Never>?
    private let defaults = UserDefaults.standard
    private static let storageKey = "focusSession.active"
    private static let notificationID = "focusSession.end"

    init() {
        // Pick a session back up if the app was closed while it was running.
        if let data = defaults.data(forKey: Self.storageKey),
           let saved = try? JSONDecoder().decode(Active.self, from: data),
           saved.end > .now {
            active = saved
            UIApplication.shared.isIdleTimerDisabled = true
            armTimer()
        } else {
            defaults.removeObject(forKey: Self.storageKey)
        }
    }

    /// Starts focusing on `item`. A running event is focused until it ends;
    /// anything else gets a session of `minutes`.
    func start(on item: AgendaItem, minutes: Int, now: Date = .now) {
        let end: Date
        if item.isInProgress(at: now), let eventEnd = item.end {
            end = eventEnd
        } else {
            end = now.addingTimeInterval(TimeInterval(max(1, minutes)) * 60)
        }

        let session = Active(item: item, start: now, end: end)
        active = session
        if let data = try? JSONEncoder().encode(session) {
            defaults.set(data, forKey: Self.storageKey)
        }
        UIApplication.shared.isIdleTimerDisabled = true
        armTimer()
        scheduleNotification(for: session)
    }

    /// Ends the session early.
    func stop() {
        clear()
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [Self.notificationID])
    }

    /// Call when the app returns to the foreground: timers do not run while suspended.
    func reconcile() {
        guard let active else { return }
        if active.end <= .now {
            clear()
        } else {
            armTimer()
        }
    }

    private func finish() {
        clear()
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    private func clear() {
        timer?.cancel()
        timer = nil
        active = nil
        defaults.removeObject(forKey: Self.storageKey)
        UIApplication.shared.isIdleTimerDisabled = false
    }

    private func armTimer() {
        timer?.cancel()
        guard let end = active?.end else { return }
        timer = Task { [weak self] in
            let wait = max(0, end.timeIntervalSinceNow)
            try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.finish()
        }
    }

    /// Lets the user know the session ended if the phone is locked or the app
    /// is in the background. Silently does nothing if notifications are refused.
    private func scheduleNotification(for session: Active) {
        let center = UNUserNotificationCenter.current()
        let title = session.item.title
        let interval = max(1, session.end.timeIntervalSinceNow)
        Task {
            guard (try? await center.requestAuthorization(options: [.alert, .sound])) == true else { return }
            let content = UNMutableNotificationContent()
            content.title = "Focus session complete"
            content.body = title
            content.sound = .default
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
            let request = UNNotificationRequest(
                identifier: Self.notificationID, content: content, trigger: trigger)
            try? await center.add(request)
        }
    }
}
