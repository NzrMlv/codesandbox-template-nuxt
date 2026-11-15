# Focus Next (iOS)

A one-screen focus app built on your Apple Calendar and Apple Reminders.

- **Ring**: time left in the current event, or time until the next event / timed reminder.
- **Play**: start a focus session on whatever the ring shows. A running event is focused until it ends; anything else uses the length you pick (15 / 25 / 45 / 60 min).
- **Today**: all-day events, the timed schedule, and tasks (date-only and overdue reminders). Tick reminders off right in the list; that writes back to Apple Reminders.

All data comes from EventKit on the device. Nothing is stored or sent anywhere.

## Run it

Requires a Mac with Xcode 16 or newer, and iOS 17+.

1. Open `ios/FocusNext.xcodeproj`.
2. Select the **FocusNext** target → *Signing & Capabilities* → choose your team (and change the bundle identifier from `com.example.FocusNext` if Xcode asks).
3. Run on your iPhone and allow Calendar and Reminders access.

The simulator works too, but its calendar is empty until you add events in the simulator's Calendar app.

If the project file does not open in your Xcode version, install [XcodeGen](https://github.com/yonaskolb/XcodeGen) and run `xcodegen` in this folder to regenerate it from `project.yml`.

## Layout

| Path | What it holds |
| --- | --- |
| `FocusNext/Model` | Plain-Swift logic: agenda items, "current / next" rules, countdown formatting |
| `FocusNext/Services/CalendarStore.swift` | EventKit access, fetching, completing reminders |
| `FocusNext/Services/FocusSession.swift` | The focus timer, its end-of-session notification |
| `FocusNext/Views` | The single screen and its components |
