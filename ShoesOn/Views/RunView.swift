import StoreKit
import SwiftUI

/// The routine in progress: one step at a time, a dial for it, and whether the
/// morning is on schedule. Then the walk out, then how it went. Always dark,
/// with a slow light behind it in the colour of the status.
struct RunView: View {
    @EnvironmentObject private var store: RoutineStore
    /// What the cover last had to show, kept through its dismissal so the
    /// slide-down never shows an empty sheet.
    @State private var lastShown: Content?

    private enum Content: Hashable {
        case run(ActiveRun)
        case finished(FinishedRun)
    }

    private var current: Content? {
        if let run = store.activeRun { return .run(run) }
        if let finished = store.state.lastFinished { return .finished(finished) }
        return nil
    }

    var body: some View {
        Group {
            switch current ?? lastShown {
            case .run(let run):
                ActiveRunScreen(run: run)
                    .environment(\.colorScheme, .dark)
                    .preferredColorScheme(.dark)
            case .finished(let finished):
                SummaryScreen(finished: finished)
            case nil:
                Theme.background.ignoresSafeArea()
            }
        }
        .onChange(of: current, initial: true) { _, content in
            if let content { lastShown = content }
        }
    }
}

/// The run's backdrop: near-black with a soft glow that drifts, tinted by the
/// status. A mesh gradient on iOS 18, a radial one before it.
struct StatusGlow: View {
    let color: Color
    /// Drifts the glow back and forth on one slow animation, so the backdrop
    /// costs nothing while the run's clock ticks for an hour.
    @State private var drifted = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Theme.night
            if #available(iOS 18.0, *) {
                let drift: Float = drifted ? 0.08 : -0.08
                MeshGradient(
                    width: 3,
                    height: 3,
                    points: [
                        [0, 0], [0.5, 0], [1, 0],
                        [0, 0.5], [0.5 + drift, 0.45 - drift], [1, 0.5],
                        [0, 1], [0.5 - drift, 1], [1, 1],
                    ],
                    colors: [
                        Theme.night, color.opacity(0.35), Theme.night,
                        Theme.night, color.opacity(0.22), Theme.night,
                        color.opacity(0.10), Theme.night, color.opacity(0.18),
                    ]
                )
                .animation(.easeInOut(duration: 9).repeatForever(autoreverses: true), value: drifted)
                .onAppear { if !reduceMotion { drifted = true } }
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
    /// The undo on offer, while it shows.
    @State private var undoOffered: UUID?
    @Environment(\.dynamicTypeSize) private var typeSize

    /// Unfolded, the run shares a landscape display about 670 pt tall.
    @State private var isSplit = false

    /// The dial gives up room to the text at accessibility sizes, and to the
    /// short landscape pane unfolded, so Done never leaves the screen.
    private var dialSize: CGFloat { typeSize.isAccessibilitySize || isSplit ? 190 : 260 }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let now = AppClock.adjust(context.date)
            let status = run.status(now: now)
            let isOverdue = now >= (run.isLeaving ? run.leaveAt : run.stepEndsAt)
            ZStack {
                StatusGlow(color: Theme.color(for: status))
                // Unfolded, the whole morning sits beside the step in hand.
                FoldSplit { split in
                    VStack(spacing: 0) {
                        topBar
                            // Landscape has no status bar above the pane.
                            .padding(.top, split ? 12 : 0)
                        Spacer(minLength: 8)
                        // Overlaid, not stacked, so the face that leaves never
                        // holds space against the one that arrives.
                        ZStack {
                            if run.isLeaving {
                                leaving(now: now)
                                    .transition(.stepChange)
                            } else {
                                stepFace(now: now, status: status)
                                    .transition(.stepChange)
                            }
                        }
                        Spacer(minLength: 8)
                        controls
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 8)
                    .onChange(of: split, initial: true) { _, split in isSplit = split }
                } secondary: {
                    RunPlanPane(run: run, now: now, status: status)
                }
            }
            // A buzz the moment time runs out, for when the phone is
            // propped on the counter and nobody is looking at it.
            .sensoryFeedback(trigger: isOverdue) { _, overdue in overdue ? .warning : nil }
        }
        .sensoryFeedback(.success, trigger: run.stepIndex)
        #if DEBUG
        // Capture-only: a real Done, then its Undo, so a native recording
        // shows the step hand-over and lands back where it began.
        .task {
            guard ScreenshotConfig.has("-CaptureTour") else { return }
            try? await Task.sleep(for: .seconds(9))
            // On the app clock, which `-FixedNow` moves, like the seeded run.
            withAnimation(.smooth) { store.completeStep(now: AppClock.now) }
            try? await Task.sleep(for: .seconds(4))
            withAnimation(.smooth) {
                undoOffered = nil
                store.undoLastStep()
            }
        }
        #endif
        .onChange(of: store.lastStepUndo?.id) { _, id in
            withAnimation(.smooth) { undoOffered = id }
        }
        .task(id: undoOffered) {
            guard undoOffered != nil else { return }
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            withAnimation(.smooth) { undoOffered = nil }
        }
        // One screen with no scrolling: text grows up to the first
        // accessibility size, where everything still fits with Done in reach.
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        // Mornings happen with the phone on the counter: the screen stays on
        // for as long as a routine runs.
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
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
                        .lineLimit(1)
                    Text(run.isPracticeRun ? "Practice run · ready by \(Format.time(run.leaveAt))" : "Out the door \(Format.time(run.leaveAt))")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.92))
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
        // The ring stays and refills; the words in and around it hand over
        // to the next step's, the old ones gone before the new ones land.
        return VStack(spacing: 26) {
            ZStack {
                VStack(spacing: 6) {
                    Text("Step \(run.planStepNumber) of \(run.planStepCount)")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(.white.opacity(0.92))
                        .textCase(.uppercase)
                        .tracking(1)
                    Text(run.currentStep?.name ?? "")
                        .displayFont(38)
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .minimumScaleFactor(0.6)
                        .lineLimit(2)
                }
                .id(run.stepIndex)
                .transition(.stepChange)
            }
            Dial(remaining: remaining / planned, color: Theme.color(for: status)) {
                VStack(spacing: 2) {
                    Text(Self.clock(remaining))
                        .displayFont(64, weight: .semibold, monospacedDigits: true)
                        .foregroundStyle(clockColor)
                        .minimumScaleFactor(0.3)
                        .lineLimit(1)
                        .contentTransition(.numericText(countsDown: true))
                        .frame(maxWidth: dialSize * 0.72)
                    Text(remaining >= 0 ? "left" : "over")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.92))
                }
                .accessibilityElement(children: .combine)
                .id(run.stepIndex)
                .transition(.stepChange)
            }
            .frame(width: dialSize, height: dialSize)
            ZStack {
                VStack(spacing: 12) {
                    StatusPill(status: status)
                    if let drop = run.catchUpSuggestion(now: now) {
                        catchUp(drop, status: status)
                    } else {
                        Text("Then \(run.nextStep?.name ?? "shoes on and out the door")")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.white.opacity(0.92))
                    }
                }
                .animation(.smooth, value: run.catchUpSuggestion(now: now)?.id)
                .id(run.stepIndex)
                .transition(.stepChange)
            }
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
                    .fixedSize(horizontal: false, vertical: true)
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
                .displayFont(44)
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
            } else {
                Button("Done") { advance(store.completeStep) }
                    .buttonStyle(.primary(fill: .white, text: .black))
            }
            // Right under the thumb that just tapped Done, in the slot the
            // skip button keeps, so offering it never moves anything.
            ZStack {
                if let undo = store.lastStepUndo, undoOffered == undo.id {
                    Button {
                        withAnimation(.smooth) {
                            undoOffered = nil
                            store.undoLastStep()
                        }
                    } label: {
                        Label(Self.undoTitle(undo), systemImage: "arrow.uturn.backward")
                            .lineLimit(1)
                    }
                    .buttonStyle(.secondary(.white))
                    .transition(.handOff)
                } else if !run.isLeaving {
                    Button("Skip this step") { advance(store.skipStep) }
                        .buttonStyle(.secondary(.white.opacity(0.92)))
                        .transition(.handOff)
                }
            }
            .frame(height: 44)
        }
    }

    private static func undoTitle(_ undo: StepUndo) -> String {
        switch undo.kind {
        case .done: "Undo \(undo.stepName) done"
        case .skip: "Undo \(undo.stepName) skip"
        case .drop: "Put \(undo.stepName) back"
        }
    }

    /// A second Done from a double tap would skip a step the user never did.
    private func advance(_ action: (Date) -> Void) {
        guard Date.now.timeIntervalSince(run.stepStartedAt) > 0.6 else { return }
        withAnimation(.smooth) { action(.now) }
    }

    /// "12:04" counting down, "1:36:57" past an hour, or "+3:10" once over.
    static func clock(_ seconds: TimeInterval) -> String {
        let total = Int(abs(seconds).rounded(.down))
        let text = total >= 3600
            ? String(format: "%d:%02d:%02d", total / 3600, total / 60 % 60, total % 60)
            : String(format: "%d:%02d", total / 60, total % 60)
        return seconds < 0 ? "+\(text)" : text
    }
}

/// Unfolded, the run's second screen: the whole morning beside the step in
/// hand, what is done, what is running, and when the rest should start.
private struct RunPlanPane: View {
    let run: ActiveRun
    let now: Date
    let status: RunStatus

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                timeline
            }
            .scrollBounceBehavior(.basedOnSize)
            gapCard
                .padding(.horizontal, 24)
                // Level with the bottom of Done across the fold.
                .padding(.bottom, 56)
        }
        .animation(.smooth, value: run.stepIndex)
    }

    private var timeline: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(run.isPracticeRun ? "Practice run" : "This morning")
                .font(.footnote.weight(.bold))
                .foregroundStyle(.white.opacity(0.92))
                .textCase(.uppercase)
                .tracking(1)
                .padding(.bottom, 24)
            ForEach(run.timeline(now: now)) { stop in
                row(stop)
            }
            door
        }
        .padding(.horizontal, 24)
        // Level with the leading pane's routine name across the fold.
        .padding(.top, 22)
        .padding(.bottom, 24)
    }

    /// The morning's guess against the real plan it is running on.
    private var gapCard: some View {
        let onPlan = run.steps.filter { !$0.skipped }
        return VStack(alignment: .leading, spacing: 14) {
            Text("Planned with your real times")
                .font(.footnote.weight(.bold))
                .foregroundStyle(.white.opacity(0.92))
                .textCase(.uppercase)
                .tracking(1)
            GapBars(
                guess: onPlan.reduce(0) { $0 + $1.guessMinutes },
                real: onPlan.reduce(0) { $0 + $1.plannedMinutes },
                guessFill: .white.opacity(0.28)
            )
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
    }

    private func row(_ stop: RunTimelineStop) -> some View {
        let isCurrent = stop.phase == .current
        let isPast = stop.phase == .done || stop.phase == .skipped
        return HStack(alignment: .top, spacing: 14) {
            timeLabel(stop.startsAt, emphasized: isCurrent)
            VStack(spacing: 0) {
                marker(stop.phase)
                    .frame(height: 14)
                    .padding(.top, 3)
                Rectangle()
                    .fill(.white.opacity(0.14))
                    .frame(width: 2)
                    .frame(maxHeight: .infinity)
            }
            .frame(width: 14)
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline) {
                    Text(stop.name)
                        .font(isCurrent ? .body.weight(.bold) : .body.weight(.medium))
                        .strikethrough(stop.phase == .skipped)
                        .foregroundStyle(.white.opacity(isPast ? 0.7 : 1))
                    Spacer(minLength: 8)
                    Text(stop.phase == .skipped ? "Skipped" : "\(stop.minutes) min")
                        .font(.subheadline.monospacedDigit().weight(.semibold))
                        .foregroundStyle(.white.opacity(isCurrent ? 1 : 0.55))
                }
                if isCurrent {
                    Text("Now · wrap up by \(Format.time(run.stepEndsAt))")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.color(for: status))
                }
            }
            .padding(.bottom, 22)
        }
        .accessibilityElement(children: .combine)
    }

    private var door: some View {
        HStack(alignment: .top, spacing: 14) {
            timeLabel(run.leaveAt, emphasized: true)
            Circle()
                .fill(Theme.color(for: status))
                .frame(width: 14, height: 14)
                .padding(.top, 3)
            VStack(alignment: .leading, spacing: 3) {
                Text("Out the door")
                    .font(.body.weight(.bold))
                    .foregroundStyle(.white)
                Text(run.isLeaving ? status.label : "Ready \(Format.time(run.projectedReadyAt(now: now))) · \(status.label)")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.color(for: status))
                    .contentTransition(.numericText())
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func timeLabel(_ date: Date?, emphasized: Bool) -> some View {
        Text(date.map(Format.time) ?? "")
            .font(.footnote.monospacedDigit().weight(.medium))
            .foregroundStyle(.white.opacity(emphasized ? 0.95 : 0.75))
            .fixedSize(horizontal: true, vertical: false)
            .frame(minWidth: 66, alignment: .trailing)
            .padding(.top, 2)
    }

    @ViewBuilder private func marker(_ phase: RunTimelineStop.Phase) -> some View {
        switch phase {
        case .done:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white.opacity(0.7))
        case .skipped:
            Circle()
                .strokeBorder(.white.opacity(0.3), lineWidth: 1.5)
                .frame(width: 10, height: 10)
        case .current:
            Circle()
                .fill(Theme.color(for: status))
                .frame(width: 14, height: 14)
        case .upcoming:
            Circle()
                .strokeBorder(.white.opacity(0.5), lineWidth: 2)
                .frame(width: 12, height: 12)
        }
    }
}

private extension AnyTransition {
    /// One step handing over to the next: the old words leave quickly, then
    /// the new ones settle in from the side Done sends them, so two names or
    /// two clocks never sit on top of each other mid-change.
    static var stepChange: AnyTransition {
        .asymmetric(
            insertion: .opacity.combined(with: .offset(x: 24))
                .animation(.smooth(duration: 0.38).delay(0.12)),
            removal: .opacity.combined(with: .offset(x: -24))
                .animation(.easeIn(duration: 0.12))
        )
    }

    /// The same hand-over in place, for the button under Done.
    static var handOff: AnyTransition {
        .asymmetric(
            insertion: .opacity.animation(.smooth(duration: 0.25).delay(0.1)),
            removal: .opacity.animation(.easeIn(duration: 0.1))
        )
    }
}

/// How the run went: when they left against the target, and each step's real
/// time against the guess.
private struct SummaryScreen: View {
    @EnvironmentObject private var store: RoutineStore
    @Environment(\.requestReview) private var requestReview
    let finished: FinishedRun
    @State private var shown = false

    var body: some View {
        let late = finished.run.isPracticeRun ? 0 : finished.departure.lateSeconds
        let color: Color = late <= 60 ? Theme.onTrack : late < 5 * 60 ? Theme.behind : Theme.late
        let longest = Double(finished.run.steps.map { max($0.guessMinutes, Format.minutes(fromSeconds: $0.actualSeconds ?? 0)) }.max() ?? 1)
        // Unfolded, this morning lands beside the record it just joined.
        FoldSplit { _ in
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 26) {
                        VStack(alignment: .leading, spacing: 10) {
                            Image(systemName: late <= 60 ? "checkmark.circle.fill" : "clock.badge.exclamationmark.fill")
                                .font(.system(size: 44))
                                .foregroundStyle(color)
                                .symbolEffect(.bounce, value: shown)
                            Text(headline)
                                .displayFont(40)
                                .foregroundStyle(Theme.ink)
                            Text(finished.run.isPracticeRun
                                ? "A practice run, so it doesn't count toward your on-time record."
                                : "Out the door at \(Format.time(finished.departure.left)), aiming for \(Format.time(finished.departure.target)).")
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
                Button("Done") {
                    askForReviewIfEarned()
                    withAnimation(.smooth) { store.dismissSummary() }
                }
                    .buttonStyle(.primary)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 8)
            }
        } secondary: {
            HistoryPane()
        }
        .background(Theme.background.ignoresSafeArea())
        .sensoryFeedback(.success, trigger: shown)
        .onAppear {
            withAnimation(.spring(duration: 0.9, bounce: 0.2).delay(0.1)) { shown = true }
        }
    }

    /// Asked once they have taken in the win, not over the top of it.
    private func askForReviewIfEarned() {
        guard finished.departure.wasOnTime, !finished.run.isPracticeRun else { return }
        let onTime = store.state.departures.filter(\.wasOnTime).count
        if ReviewPromptService.shared.shouldAskAfterOnTimeDeparture(onTimeCount: onTime) { requestReview() }
    }

    private var headline: String {
        if finished.run.isPracticeRun { return "Practice done." }
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
                        .accessibilityLabel("guessed \(step.guessMinutes)")
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
