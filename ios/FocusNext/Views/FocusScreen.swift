import SwiftUI
import UIKit

/// The app's only screen: what's on now, what's next, and today's plan.
struct FocusScreen: View {
    @EnvironmentObject private var store: CalendarStore
    @EnvironmentObject private var session: FocusSession
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("focusMinutes") private var focusMinutes = 25

    private static let focusLengths = [15, 25, 45, 60]

    private var agenda: Agenda { Agenda(items: store.items) }

    var body: some View {
        ZStack {
            Palette.background.ignoresSafeArea()

            switch store.access {
            case .needsPrompt:
                PermissionView(denied: false) {
                    Task { await store.requestAccess() }
                }
            case .denied:
                PermissionView(denied: true, onConnect: openSettings)
            case .ready:
                agendaView
            }
        }
        .foregroundStyle(.white)
        .task { await store.refresh() }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            session.reconcile()
            Task { await store.refresh() }
        }
        .alert("Something went wrong", isPresented: errorIsPresented) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(store.errorMessage ?? "")
        }
    }

    // MARK: - Layout

    private var agendaView: some View {
        ScrollView {
            VStack(spacing: 28) {
                // Ticks every second for the countdown.
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    hero(
                        HeroDisplay.make(agenda: agenda, session: session.active, now: context.date),
                        now: context.date
                    )
                }

                controls

                if !store.canReadEvents || !store.canReadReminders {
                    accessBanner
                }

                // The list only changes with the minute.
                TimelineView(.everyMinute) { context in
                    dayList(now: context.date)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 40)
        }
        .refreshable { await store.refresh() }
    }

    private func hero(_ display: HeroDisplay, now: Date) -> some View {
        VStack(spacing: 24) {
            VStack(alignment: .leading, spacing: 2) {
                Text(display.heading)
                    .font(.largeTitle.bold())
                Text(now.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                    .font(.subheadline)
                    .foregroundStyle(Palette.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            RingView(
                progress: display.progress,
                tint: display.tint.color,
                caption: display.caption,
                value: display.value,
                detail: display.detail
            )
            .frame(maxWidth: 360)

            if !display.title.isEmpty {
                Text(display.title)
                    .font(.title.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
            }
        }
    }

    private var controls: some View {
        HStack(spacing: 30) {
            Menu {
                Picker("Focus length", selection: $focusMinutes) {
                    ForEach(Self.focusLengths, id: \.self) { minutes in
                        Text("\(minutes) minutes").tag(minutes)
                    }
                }
            } label: {
                RoundButtonLabel {
                    Text("\(focusMinutes)m").font(.callout.weight(.semibold))
                }
            }
            .disabled(session.active != nil)
            .opacity(session.active == nil ? 1 : 0.4)
            .accessibilityLabel("Focus length, \(focusMinutes) minutes")

            Button {
                if session.active == nil {
                    session.start(on: focusTarget(), minutes: focusMinutes)
                } else {
                    session.stop()
                }
            } label: {
                RoundButtonLabel(size: 88) {
                    Image(systemName: session.active == nil ? "play.fill" : "stop.fill")
                        .font(.system(size: 32))
                }
            }
            .accessibilityLabel(session.active == nil ? "Start focus" : "Stop focus")

            // Finishing a reminder you are focused on ticks it off in Reminders.
            if let reminder = focusedReminder {
                Button {
                    store.setCompleted(reminder, true)
                    session.stop()
                } label: {
                    RoundButtonLabel {
                        Image(systemName: "checkmark").font(.title3.weight(.semibold))
                    }
                }
                .accessibilityLabel("Mark as done")
            } else {
                Color.clear.frame(width: 60, height: 60)
            }
        }
    }

    private var accessBanner: some View {
        HStack {
            Text("\(store.canReadEvents ? "Reminders" : "Calendar") access is off, so this list is incomplete.")
                .font(.footnote)
                .foregroundStyle(Palette.secondary)
            Spacer()
            Button("Settings", action: openSettings)
                .font(.footnote.weight(.semibold))
        }
        .padding(14)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 16))
    }

    @ViewBuilder
    private func dayList(now: Date) -> some View {
        let day = agenda.day(at: now)

        if day.isEmpty {
            Text("Nothing planned for today")
                .foregroundStyle(Palette.secondary)
                .padding(.top, 12)
        } else {
            VStack(alignment: .leading, spacing: 24) {
                section("All day", day.allDay, now: now)
                section("Schedule", day.timeline, now: now)
                section("Tasks", day.tasks, now: now)
            }
        }
    }

    @ViewBuilder
    private func section(_ title: String, _ items: [AgendaItem], now: Date) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(title.uppercased())
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Palette.secondary)
                    .padding(.leading, 4)

                ForEach(items) { item in
                    AgendaRow(
                        item: item,
                        now: now,
                        isFocused: session.active?.item.id == item.id,
                        onToggle: { store.setCompleted(item, !item.isCompleted) },
                        onFocus: { session.start(on: item, minutes: focusMinutes) }
                    )
                }
            }
        }
    }

    // MARK: - Helpers

    /// What the big play button focuses on: the current event, else the next
    /// item, else the first open task, else a free-form session.
    private func focusTarget() -> AgendaItem {
        let now = Date.now
        if let item = HeroDisplay.make(agenda: agenda, session: nil, now: now).item {
            return item
        }
        return AgendaItem(
            id: "free-focus",
            kind: .reminder,
            title: "Focus session",
            date: now,
            end: nil,
            hasTime: true,
            calendarTitle: ""
        )
    }

    /// The open reminder being focused on, if it still exists in Reminders.
    private var focusedReminder: AgendaItem? {
        guard let id = session.active?.item.id else { return nil }
        return store.items.first { $0.id == id && $0.kind == .reminder && !$0.isCompleted }
    }

    private var errorIsPresented: Binding<Bool> {
        Binding(
            get: { store.errorMessage != nil },
            set: { if !$0 { store.errorMessage = nil } }
        )
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}
