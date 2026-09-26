import SwiftUI

/// The routine in progress: one step at a time, a dial for it, and whether the
/// morning is on schedule. Then the walk out, then how it went. Always dark,
/// with a slow light behind it in the colour of the status.
struct RunView: View {
    @EnvironmentObject private var store: RoutineStore

    var body: some View {
        Group {
            if let run = store.activeRun {
                ActiveRunScreen(run: run)
                    .environment(\.colorScheme, .dark)
                    .preferredColorScheme(.dark)
            } else if let finished = store.state.lastFinished {
                SummaryScreen(finished: finished)
            }
        }
    }
}

/// The run's backdrop: near-black with a soft glow that drifts, tinted by the
/// status. A mesh gradient on iOS 18, a radial one before it.
struct StatusGlow: View {
    let color: Color

    var body: some View {
        ZStack {
            Theme.night
            if #available(iOS 18.0, *) {
                TimelineView(.animation(minimumInterval: 1 / 20)) { context in
                    let t = context.date.timeIntervalSinceReferenceDate
                    let drift = Float(sin(t / 3) * 0.08)
                    let drift2 = Float(cos(t / 4) * 0.08)
                    MeshGradient(
                        width: 3,
                        height: 3,
                        points: [
                            [0, 0], [0.5, 0], [1, 0],
                            [0, 0.5], [0.5 + drift, 0.45 + drift2], [1, 0.5],
                            [0, 1], [0.5 - drift2, 1], [1, 1],
                        ],
                        colors: [
                            Theme.night, color.opacity(0.35), Theme.night,
                            Theme.night, color.opacity(0.22), Theme.night,
                            color.opacity(0.10), Theme.night, color.opacity(0.18),
                        ]
                    )
                }
            } else {
                RadialGradient(colors: [color.opacity(0.28), .clear], center: .top, startRadius: 0, endRadius: 520)
            }
        }
        .animation(.easeInOut(duration: 1.2), value: color)
        .ignoresSafeArea()
    }
}

private struct ActiveRunScreen: View {
    @EnvironmentObject private var store: RoutineStore
    let run: ActiveRun
    @State private var confirmEnd = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let now = AppClock.adjust(context.date)
            let status = run.status(now: now)
            ZStack {
                StatusGlow(color: Theme.color(for: status))
                VStack(spacing: 0) {
                    topBar
                    Spacer(minLength: 8)
                    if run.isLeaving {
                        leaving(now: now)
                    } else {
                        stepFace(now: now, status: status)
                    }
                    Spacer(minLength: 8)
                    controls
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 8)
            }
        }
        .sensoryFeedback(.success, trigger: run.stepIndex)
        .confirmationDialog("End this routine?", isPresented: $confirmEnd, titleVisibility: .visible) {
            Button("End without leaving", role: .destructive) { store.cancelRun() }
        } message: {
            Text("Steps you finished still count toward your real times.")
        }
    }

    private var topBar: some View {
        VStack(spacing: 14) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(run.routineName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                    Text("Out the door \(Format.time(run.leaveAt))")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.6))
                }
                Spacer()
                IconButton(symbol: "xmark", label: "End routine", tint: .white) { confirmEnd = true }
            }
            HStack(spacing: 5) {
                ForEach(run.steps.indices, id: \.self) { index in
                    Capsule()
                        .fill(progressFill(index))
                        .frame(height: 4)
                }
            }
            .animation(.smooth, value: run.stepIndex)
            .accessibilityHidden(true)
        }
        .padding(.top, 8)
    }

    private func progressFill(_ index: Int) -> Color {
        if run.steps[index].skipped { return .white.opacity(0.05) }
        if index < run.stepIndex { return .white }
        return index == run.stepIndex ? .white.opacity(0.45) : .white.opacity(0.14)
    }

    private func stepFace(now: Date, status: RunStatus) -> some View {
        let remaining = run.stepEndsAt.timeIntervalSince(now)
        let planned = max(run.currentStep?.plannedSeconds ?? 1, 1)
        let clockColor = remaining >= 0 ? Color.white : Theme.color(for: status)
        return VStack(spacing: 26) {
            VStack(spacing: 6) {
                Text("Step \(run.planStepNumber) of \(run.planStepCount)")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(.white.opacity(0.55))
                    .textCase(.uppercase)
                    .tracking(1)
                Text(run.currentStep?.name ?? "")
                    .font(.system(size: 38, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.6)
                    .lineLimit(2)
                    .id(run.stepIndex)
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))
            }
            Dial(remaining: remaining / planned, color: Theme.color(for: status)) {
                VStack(spacing: 2) {
                    Text(Self.clock(remaining))
                        .font(.system(size: 64, weight: .semibold, design: .rounded).monospacedDigit())
                        .foregroundStyle(clockColor)
                        .contentTransition(.numericText(countsDown: true))
                    Text(remaining >= 0 ? "left" : "over")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.55))
                }
                .accessibilityElement(children: .combine)
            }
            .frame(width: 260, height: 260)
            VStack(spacing: 12) {
                StatusPill(status: status)
                if let drop = run.catchUpSuggestion(now: now) {
                    catchUp(drop, status: status)
                } else {
                    Text("Then \(run.nextStep?.name ?? "shoes on and out the door")")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
            .animation(.smooth, value: run.catchUpSuggestion(now: now)?.id)
        }
        .animation(.smooth(duration: 0.4), value: run.stepIndex)
    }

    /// Behind, with a way back: the one later step whose time would cover it.
    private func catchUp(_ step: RunStep, status: RunStatus) -> some View {
        let color = Theme.color(for: status)
        return Button {
            withAnimation(.smooth) { store.dropUpcomingStep(id: step.id) }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "scissors")
                    .font(.footnote.weight(.bold))
                Text("Skip \(step.name) today, win back \(step.plannedMinutes) min")
                    .font(.subheadline.weight(.semibold))
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .frame(minHeight: 44)
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(color.opacity(0.6), lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.impact(weight: .light), trigger: run.upcomingSteps.count)
        .transition(.opacity.combined(with: .scale(scale: 0.95)))
        .accessibilityHint("Takes \(step.name) off this morning's plan")
    }

    private func leaving(now: Date) -> some View {
        let untilLeave = run.leaveAt.timeIntervalSince(now)
        return VStack(spacing: 22) {
            Image(systemName: "figure.walk.departure")
                .font(.system(size: 64, weight: .semibold))
                .foregroundStyle(.white)
                .symbolEffect(.bounce, value: run.stepIndex)
                .accessibilityHidden(true)
            Text(untilLeave > 0 ? "Shoes on." : "Time to go.")
                .font(.system(size: 44, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
            Text(untilLeave > 0 ? "\(Self.clock(untilLeave)) to spare" : "\(Self.clock(untilLeave)) past \(Format.time(run.leaveAt))")
                .font(.system(.title2, design: .rounded).monospacedDigit().weight(.bold))
                .foregroundStyle(untilLeave > 0 ? Theme.onTrack : Theme.late)
                .contentTransition(.numericText())
        }
    }

    private var controls: some View {
        VStack(spacing: 4) {
            if run.isLeaving {
                Button("I'm out the door") { withAnimation(.smooth) { _ = store.finishRun() } }
                    .buttonStyle(.primary(fill: .white, text: .black))
                Color.clear.frame(height: 44)
            } else {
                Button("Done") { withAnimation(.smooth) { store.completeStep() } }
                    .buttonStyle(.primary(fill: .white, text: .black))
                Button("Skip this step") { withAnimation(.smooth) { store.skipStep() } }
                    .buttonStyle(.secondary(.white.opacity(0.6)))
            }
        }
    }

    /// "12:04" counting down, or "+3:10" once over.
    static func clock(_ seconds: TimeInterval) -> String {
        let total = Int(abs(seconds).rounded(.down))
        let text = String(format: "%d:%02d", total / 60, total % 60)
        return seconds < 0 ? "+\(text)" : text
    }
}

/// How the run went: when they left against the target, and each step's real
/// time against the guess.
private struct SummaryScreen: View {
    @EnvironmentObject private var store: RoutineStore
    @EnvironmentObject private var review: ReviewPromptService
    let finished: FinishedRun
    @State private var shown = false

    var body: some View {
        let late = finished.departure.lateSeconds
        let color: Color = late <= 60 ? Theme.onTrack : late < 5 * 60 ? Theme.behind : Theme.late
        let longest = Double(finished.run.steps.map { max($0.guessMinutes, Format.minutes(fromSeconds: $0.actualSeconds ?? 0)) }.max() ?? 1)
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    VStack(alignment: .leading, spacing: 10) {
                        Image(systemName: late <= 60 ? "checkmark.circle.fill" : "clock.badge.exclamationmark.fill")
                            .font(.system(size: 44))
                            .foregroundStyle(color)
                            .symbolEffect(.bounce, value: shown)
                        Text(headline)
                            .font(.system(size: 40, weight: .heavy, design: .rounded))
                            .foregroundStyle(Theme.ink)
                        Text("Out the door at \(Format.time(finished.departure.left)), aiming for \(Format.time(finished.departure.target)).")
                            .font(.body)
                            .foregroundStyle(Theme.secondary)
                    }
                    .padding(.top, 28)
                    Card {
                        SectionLabel("Guess vs real")
                            .padding(.bottom, 14)
                        VStack(spacing: 16) {
                            ForEach(finished.run.steps) { step in
                                StepCompare(step: step, longest: longest, shown: shown)
                            }
                        }
                    }
                    Text("Your next plan already uses these times.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondary)
                }
                .padding(.horizontal, 20)
            }
            Button("Done") { withAnimation(.smooth) { store.dismissSummary() } }
                .buttonStyle(.primary)
                .padding(.horizontal, 24)
                .padding(.bottom, 8)
        }
        .background(Theme.background.ignoresSafeArea())
        .sensoryFeedback(.success, trigger: shown)
        .onAppear {
            withAnimation(.spring(duration: 0.9, bounce: 0.2).delay(0.1)) { shown = true }
            guard finished.departure.wasOnTime else { return }
            let onTime = store.state.departures.filter(\.wasOnTime).count
            review.considerAfterOnTimeDeparture(onTimeCount: onTime)
        }
    }

    private var headline: String {
        let late = finished.departure.lateSeconds
        if late <= 60 && late >= -60 { return "Right on time." }
        if late < 0 { return "\(Int((-late / 60).rounded())) min early." }
        return "\(Int((late / 60).rounded())) min late."
    }
}

/// One step: the guess as a pale bar, the real time as a bright one over it.
private struct StepCompare: View {
    let step: RunStep
    let longest: Double
    let shown: Bool

    var body: some View {
        let took = step.actualSeconds.map { Format.minutes(fromSeconds: $0) }
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(step.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                Spacer()
                if step.skipped {
                    Text("Skipped").foregroundStyle(Theme.secondary)
                } else if let took {
                    Text("\(step.guessMinutes)").strikethrough().foregroundStyle(Theme.secondary)
                    Text("\(took) min").foregroundStyle(Theme.ink)
                }
            }
            .font(.subheadline.monospacedDigit().weight(.semibold))
            GeometryReader { proxy in
                VStack(alignment: .leading, spacing: 3) {
                    Capsule()
                        .fill(Theme.raised)
                        .frame(width: shown ? proxy.size.width * CGFloat(Double(step.guessMinutes) / longest) : 8, height: 5)
                    if let took {
                        Capsule()
                            .fill(took > step.guessMinutes ? Theme.gap : Theme.onTrack)
                            .frame(width: shown ? proxy.size.width * CGFloat(Double(took) / longest) : 8, height: 5)
                    }
                }
            }
            .frame(height: 13)
        }
        .accessibilityElement(children: .combine)
    }
}
