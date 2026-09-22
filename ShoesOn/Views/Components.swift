import SwiftUI

/// Full-width ink button: the one primary action on a screen.
struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(Theme.inkInverse)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(Theme.ink.opacity(isEnabled ? 1 : 0.35), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .opacity(configuration.isPressed ? 0.82 : 1)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// Quiet text button for secondary actions.
struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Theme.secondary)
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    static var primary: PrimaryButtonStyle { PrimaryButtonStyle() }
}

extension ButtonStyle where Self == SecondaryButtonStyle {
    static var secondary: SecondaryButtonStyle { SecondaryButtonStyle() }
}

/// A plain surface card.
struct Card<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0, content: content)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                    .strokeBorder(Theme.hairline, lineWidth: 1)
            )
    }
}

/// On track, ahead, or behind, in the colour that says so.
struct StatusPill: View {
    let status: RunStatus

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(Theme.color(for: status))
                .frame(width: 8, height: 8)
            Text(status.label)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.color(for: status))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(Theme.color(for: status).opacity(0.12), in: Capsule())
        .accessibilityElement(children: .combine)
    }
}

/// Small uppercase label above a section of a card.
struct SectionLabel: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Theme.secondary)
            .textCase(.uppercase)
            .tracking(0.4)
    }
}

/// One step as the plan sees it: the guess, and the time it really needs.
struct PlanStepRow: View {
    let planned: PlannedStep

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(Format.time(planned.startsAt))
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(Theme.secondary)
                .frame(minWidth: 64, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(planned.step.name)
                    .font(.body)
                    .foregroundStyle(Theme.ink)
                Text(sourceText)
                    .font(.footnote)
                    .foregroundStyle(Theme.secondary)
            }
            Spacer(minLength: 8)
            Text(Format.duration(minutes: planned.estimate.minutes))
                .font(.body.monospacedDigit().weight(.semibold))
                .foregroundStyle(Theme.ink)
        }
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
    }

    private var sourceText: String {
        let guess = "Guess \(planned.estimate.guessMinutes)"
        switch planned.estimate.source {
        case .pace: return "\(guess) · your pace"
        case .learned(let runs): return "\(guess) · \(runs) \(runs == 1 ? "run" : "runs")"
        }
    }
}

/// Seven round day toggles in the locale's week order.
struct WeekdayPicker: View {
    @Binding var selection: Set<Int>

    var body: some View {
        let symbols = Calendar.current.veryShortWeekdaySymbols
        HStack(spacing: 6) {
            ForEach(Format.orderedWeekdays(), id: \.self) { day in
                let isOn = selection.contains(day)
                Button {
                    if isOn { selection.remove(day) } else { selection.insert(day) }
                } label: {
                    Text(symbols[day - 1])
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                        .foregroundStyle(isOn ? Theme.inkInverse : Theme.ink)
                        .background(isOn ? Theme.ink : Theme.surface, in: Circle())
                        .overlay(Circle().strokeBorder(Theme.hairline, lineWidth: isOn ? 0 : 1))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Calendar.current.weekdaySymbols[day - 1])
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
    }
}
