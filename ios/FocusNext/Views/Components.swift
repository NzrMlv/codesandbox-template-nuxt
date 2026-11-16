import SwiftUI

enum Palette {
    static let background = Color(red: 0.035, green: 0.043, blue: 0.047)
    static let surface = Color.white.opacity(0.07)
    static let track = Color.white.opacity(0.06)
    static let secondary = Color.white.opacity(0.55)
    static let warning = Color(red: 1.0, green: 0.62, blue: 0.35)
}

extension AgendaItem.Tint {
    var color: Color { Color(red: red, green: green, blue: blue) }
}

// MARK: - Ring

struct RingView: View {
    var progress: Double
    var tint: Color
    var caption: String
    var value: String
    var detail: String

    private let lineWidth: CGFloat = 26

    var body: some View {
        ZStack {
            Circle()
                .stroke(Palette.track, lineWidth: lineWidth)

            Circle()
                // Always leave a visible dot so the ring never looks empty.
                .trim(from: 0, to: max(0.004, progress))
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .shadow(color: tint.opacity(0.45), radius: 16)
                .animation(.easeInOut(duration: 0.6), value: progress)

            VStack(spacing: 6) {
                Text(caption)
                    .font(.title3)
                    .foregroundStyle(Palette.secondary)
                Text(value)
                    .font(.system(size: 68, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .contentTransition(.numericText())
                    .animation(.default, value: value)
                Text(detail)
                    .font(.title3)
                    .foregroundStyle(Palette.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
            }
            .padding(.horizontal, lineWidth + 24)
        }
        .padding(lineWidth / 2)
        .aspectRatio(1, contentMode: .fit)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Round buttons

struct RoundButtonLabel<Content: View>: View {
    var size: CGFloat
    var content: Content

    init(size: CGFloat = 60, @ViewBuilder content: () -> Content) {
        self.size = size
        self.content = content()
    }

    var body: some View {
        content
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Palette.surface, in: Circle())
            .overlay(Circle().strokeBorder(Color.white.opacity(0.08)))
            .contentShape(Circle())
    }
}

// MARK: - List row

struct AgendaRow: View {
    var item: AgendaItem
    var now: Date
    var isFocused: Bool
    var onToggle: () -> Void
    var onFocus: () -> Void

    private var isDimmed: Bool { item.isCompleted || item.isOver(at: now) }

    var body: some View {
        HStack(spacing: 14) {
            leading

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(item.title)
                        .font(.body.weight(.medium))
                        .strikethrough(item.isCompleted)
                        .lineLimit(2)
                    if item.isInProgress(at: now) {
                        Text("Now")
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(item.tint.color.opacity(0.3), in: Capsule())
                    }
                }
                subtitle
                    .font(.footnote)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            if isFocused {
                Image(systemName: "timer")
                    .foregroundStyle(item.tint.color)
                    .accessibilityLabel("Focusing")
            } else if !isDimmed {
                Button(action: onFocus) {
                    Image(systemName: "play.fill")
                        .font(.footnote)
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background(Palette.surface, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Focus on \(item.title)")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color.white.opacity(isFocused ? 0.13 : 0.07), in: RoundedRectangle(cornerRadius: 16))
        .opacity(isDimmed ? 0.45 : 1)
    }

    @ViewBuilder
    private var leading: some View {
        switch item.kind {
        case .event:
            RoundedRectangle(cornerRadius: 2)
                .fill(item.tint.color)
                .frame(width: 4, height: 36)
                .padding(.horizontal, 10)
        case .reminder:
            Button(action: onToggle) {
                Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(item.tint.color)
                    .frame(width: 24, height: 36)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(item.isCompleted ? "Mark as not done" : "Mark as done")
        }
    }

    private var subtitle: some View {
        var parts: [String] = []
        if item.kind == .event {
            if item.hasTime, let end = item.end {
                parts.append("\(HeroDisplay.time(item.date)) – \(HeroDisplay.time(end))")
            } else {
                parts.append("All day")
            }
        } else if item.hasTime {
            parts.append(HeroDisplay.time(item.date))
        }
        if !item.calendarTitle.isEmpty { parts.append(item.calendarTitle) }
        if let location = item.location { parts.append(location) }

        let overdue = item.isOverdue(at: now)
        let text = (overdue ? ["Overdue"] + parts : parts).joined(separator: " · ")
        return Text(text).foregroundStyle(overdue ? Palette.warning : Palette.secondary)
    }
}

// MARK: - Permission states

struct PermissionView: View {
    var denied: Bool
    var onConnect: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "calendar.badge.clock")
                .font(.system(size: 56))
                .foregroundStyle(AgendaItem.Tint.fallback.color)
            Text(denied ? "No access to your day" : "See what's next")
                .font(.title.bold())
            Text(denied
                 ? "Focus Next needs full access to Calendar or Reminders to show your plan. You can turn it on in Settings."
                 : "Focus Next reads your Apple Calendar events and Reminders to show what's happening now and what's coming up. Nothing leaves your phone.")
                .foregroundStyle(Palette.secondary)
                .multilineTextAlignment(.center)
            Button(action: onConnect) {
                Text(denied ? "Open Settings" : "Connect Calendar & Reminders")
                    .font(.headline)
                    .foregroundStyle(.black)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 14)
                    .background(AgendaItem.Tint.fallback.color, in: Capsule())
            }
            .padding(.top, 8)
        }
        .padding(32)
    }
}
