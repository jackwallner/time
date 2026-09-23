import SwiftUI

// MARK: - Buttons

/// Full-width capsule: the one primary action on a screen. Liquid Glass on
/// iOS 26, a solid fill before it.
struct PrimaryButtonStyle: ButtonStyle {
    var fill: Color = Theme.ink
    var text: Color = Theme.inkInverse
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(text)
            .frame(maxWidth: .infinity)
            .frame(height: 58)
            .modifier(CapsuleFill(fill: fill.opacity(isEnabled ? 1 : 0.35)))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(duration: 0.25, bounce: 0.4), value: configuration.isPressed)
    }
}

private struct CapsuleFill: ViewModifier {
    let fill: Color

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .background(fill, in: Capsule())
                .glassEffect(.regular.tint(fill).interactive(), in: Capsule())
        } else {
            content.background(fill, in: Capsule())
        }
    }
}

/// Quiet text button for secondary actions.
struct SecondaryButtonStyle: ButtonStyle {
    var color: Color = Theme.secondary

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(color)
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.5 : 1)
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    static var primary: PrimaryButtonStyle { PrimaryButtonStyle() }
    static func primary(fill: Color, text: Color) -> PrimaryButtonStyle { PrimaryButtonStyle(fill: fill, text: text) }
}

extension ButtonStyle where Self == SecondaryButtonStyle {
    static var secondary: SecondaryButtonStyle { SecondaryButtonStyle() }
    static func secondary(_ color: Color) -> SecondaryButtonStyle { SecondaryButtonStyle(color: color) }
}

/// Round icon button used in toolbars and on the run screen.
struct IconButton: View {
    let symbol: String
    let label: String
    var tint: Color = Theme.ink
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 44, height: 44)
                .modifier(GlassCircle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

private struct GlassCircle: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular.interactive(), in: Circle())
        } else {
            content.background(.ultraThinMaterial, in: Circle())
        }
    }
}

// MARK: - Surfaces

/// A plain surface card.
struct Card<Content: View>: View {
    var padding: CGFloat = 20
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0, content: content)
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                    .strokeBorder(Theme.hairline.opacity(0.7), lineWidth: 1)
            )
    }
}

/// Small uppercase label above a section.
struct SectionLabel: View {
    let text: String
    var color: Color = Theme.secondary

    init(_ text: String, color: Color = Theme.secondary) {
        self.text = text
        self.color = color
    }

    var body: some View {
        Text(text)
            .font(.caption.weight(.bold))
            .foregroundStyle(color)
            .textCase(.uppercase)
            .tracking(0.8)
    }
}

/// On track, ahead, or behind, in the colour that says so.
struct StatusPill: View {
    let status: RunStatus

    var body: some View {
        let color = Theme.color(for: status)
        HStack(spacing: 7) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
                .shadow(color: color, radius: 4)
            Text(status.label)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(color)
                .contentTransition(.numericText())
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(color.opacity(0.14), in: Capsule())
        .accessibilityElement(children: .combine)
    }
}

// MARK: - The gap

/// Two bars that end at the same moment, the leave time: the guess, and the
/// real time. The part the guess leaves out is the whole point of the app.
struct GapBars: View {
    let guess: Int
    let real: Int
    var animate = true
    @State private var shown = false

    var body: some View {
        let longest = CGFloat(max(guess, real, 1))
        VStack(alignment: .leading, spacing: 10) {
            row(label: "Your guess", minutes: guess, fraction: CGFloat(guess) / longest, fill: Theme.raised, text: Theme.secondary, gap: false)
            row(label: "Real time", minutes: real, fraction: CGFloat(real) / longest, fill: Theme.ink, text: Theme.ink, gap: real > guess)
        }
        .onAppear {
            guard animate else { shown = true; return }
            withAnimation(.spring(duration: 0.9, bounce: 0.2).delay(0.15)) { shown = true }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Your guess \(Format.duration(minutes: guess)), real time \(Format.duration(minutes: real))")
    }

    private func row(label: String, minutes: Int, fraction: CGFloat, fill: Color, text: Color, gap: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label)
                Spacer()
                Text(Format.duration(minutes: minutes)).monospacedDigit()
            }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(text)
            GeometryReader { proxy in
                let width = proxy.size.width * (shown ? fraction : 0.02)
                let gapWidth = gap ? proxy.size.width * (shown ? (1 - CGFloat(guess) / CGFloat(max(real, 1))) * fraction : 0) : 0
                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                    ZStack(alignment: .leading) {
                        Capsule().fill(fill)
                        if gap {
                            Capsule()
                                .fill(Theme.gap)
                                .frame(width: max(gapWidth, 0))
                        }
                    }
                    .frame(width: max(width, 10))
                }
            }
            .frame(height: 12)
        }
    }
}

// MARK: - Plan timeline

/// The plan as a line with stops: each step's start time, its real length,
/// and the guess it replaced.
struct PlanTimeline: View {
    let plan: DeparturePlan

    var body: some View {
        VStack(spacing: 0) {
            if plan.headStartMinutes > 0 {
                stop(time: plan.alertAt, title: "Get going", detail: "You usually start a few minutes after the alert", minutes: plan.headStartMinutes, guess: nil, isFirst: true, isLast: false)
            }
            ForEach(Array(plan.steps.enumerated()), id: \.element.id) { index, planned in
                stop(
                    time: planned.startsAt,
                    title: planned.step.name,
                    detail: source(planned.estimate),
                    minutes: planned.estimate.minutes,
                    guess: planned.estimate.guessMinutes,
                    isFirst: index == 0 && plan.headStartMinutes == 0,
                    isLast: false
                )
            }
            stop(time: plan.leaveAt, title: "Out the door", detail: nil, minutes: nil, guess: nil, isFirst: false, isLast: true)
        }
    }

    private func source(_ estimate: StepEstimate) -> String {
        switch estimate.source {
        case .pace: return "Your pace"
        case .learned(let runs): return "Timed \(runs == 1 ? "once" : "\(runs) times")"
        }
    }

    private func stop(time: Date, title: String, detail: String?, minutes: Int?, guess: Int?, isFirst: Bool, isLast: Bool) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Text(Format.time(time))
                .font(.footnote.monospacedDigit().weight(.medium))
                .foregroundStyle(Theme.secondary)
                .frame(width: 66, alignment: .trailing)
                .padding(.top, 2)
            VStack(spacing: 0) {
                Circle()
                    .fill(isLast ? Theme.onTrack : Theme.ink)
                    .frame(width: isLast ? 12 : 9, height: isLast ? 12 : 9)
                    .padding(.top, isLast ? 4 : 5)
                if !isLast {
                    Rectangle()
                        .fill(Theme.hairline)
                        .frame(width: 2)
                        .frame(maxHeight: .infinity)
                }
            }
            .frame(width: 12)
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline) {
                    Text(title)
                        .font(isLast ? .body.weight(.bold) : .body.weight(.medium))
                        .foregroundStyle(Theme.ink)
                    Spacer(minLength: 8)
                    if let minutes {
                        HStack(spacing: 6) {
                            if let guess, guess != minutes {
                                Text("\(guess)")
                                    .strikethrough()
                                    .foregroundStyle(Theme.secondary)
                            }
                            Text("\(minutes) min")
                                .foregroundStyle(Theme.ink)
                        }
                        .font(.subheadline.monospacedDigit().weight(.semibold))
                    }
                }
                if let detail {
                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(Theme.secondary)
                }
            }
            .padding(.bottom, isLast ? 0 : 18)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Dial

/// A countdown ring: full when the step starts, empty when its time is up.
struct Dial<Center: View>: View {
    /// Fraction of the step's time still left, 0...1.
    let remaining: Double
    let color: Color
    var lineWidth: CGFloat = 14
    @ViewBuilder var center: () -> Center

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.10), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.001, min(remaining, 1)))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .shadow(color: color.opacity(0.6), radius: 12)
                .animation(.linear(duration: 1), value: remaining)
            center()
        }
    }
}

// MARK: - Inputs

/// Seven round day toggles in the locale's week order.
struct WeekdayPicker: View {
    @Binding var selection: Set<Int>

    var body: some View {
        let symbols = Calendar.current.veryShortWeekdaySymbols
        HStack(spacing: 6) {
            ForEach(Format.orderedWeekdays(), id: \.self) { day in
                let isOn = selection.contains(day)
                Button {
                    withAnimation(.spring(duration: 0.25)) {
                        if isOn { selection.remove(day) } else { selection.insert(day) }
                    }
                } label: {
                    Text(symbols[day - 1])
                        .font(.subheadline.weight(.bold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 42)
                        .foregroundStyle(isOn ? Theme.inkInverse : Theme.ink)
                        .background(isOn ? Theme.ink : Theme.surface, in: Circle())
                        .overlay(Circle().strokeBorder(Theme.hairline, lineWidth: isOn ? 0 : 1))
                }
                .buttonStyle(.plain)
                .sensoryFeedback(.selection, trigger: isOn)
                .accessibilityLabel(Calendar.current.weekdaySymbols[day - 1])
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
    }
}

/// "– 10 min +" in one compact control.
struct MinuteStepper: View {
    @Binding var minutes: Int

    private static let steps = [1, 2, 3, 5, 10, 15, 20, 25, 30, 40, 45, 60, 75, 90, 120]

    var body: some View {
        HStack(spacing: 0) {
            button("minus", enabled: minutes > Self.steps[0]) {
                minutes = Self.steps.last { $0 < minutes } ?? Self.steps[0]
            }
            Text("\(minutes) min")
                .font(.subheadline.monospacedDigit().weight(.bold))
                .foregroundStyle(Theme.ink)
                .contentTransition(.numericText(value: Double(minutes)))
                .frame(minWidth: 56)
            button("plus", enabled: minutes < Self.steps.last!) {
                minutes = Self.steps.first { $0 > minutes } ?? minutes
            }
        }
        .background(Theme.raised, in: Capsule())
        .animation(.snappy, value: minutes)
        .sensoryFeedback(.selection, trigger: minutes)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(minutes) minutes")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: minutes = Self.steps.first { $0 > minutes } ?? minutes
            case .decrement: minutes = Self.steps.last { $0 < minutes } ?? minutes
            @unknown default: break
            }
        }
    }

    private func button(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.footnote.weight(.bold))
                .frame(width: 32, height: 32)
                .foregroundStyle(enabled ? Theme.ink : Theme.secondary.opacity(0.4))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}
