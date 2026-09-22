import SwiftUI

/// The routine in progress: one step at a time, a clock for it, and whether
/// the morning is on schedule. Then the walk out, then how it went.
struct RunView: View {
    @EnvironmentObject private var store: RoutineStore

    var body: some View {
        Group {
            if let run = store.activeRun {
                ActiveRunScreen(run: run)
            } else if let finished = store.state.lastFinished {
                SummaryScreen(finished: finished)
            }
        }
        .background(Theme.background.ignoresSafeArea())
    }
}

private struct ActiveRunScreen: View {
    @EnvironmentObject private var store: RoutineStore
    let run: ActiveRun
    @State private var confirmEnd = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let now = context.date
            VStack(spacing: 0) {
                topBar
                Spacer(minLength: 12)
                if run.isLeaving {
                    leaving(now: now)
                } else {
                    stepFace(now: now)
                }
                Spacer(minLength: 12)
                controls
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 12)
        }
        .sensoryFeedback(.success, trigger: run.stepIndex)
        .confirmationDialog("End this routine?", isPresented: $confirmEnd, titleVisibility: .visible) {
            Button("End without leaving", role: .destructive) { store.cancelRun() }
        } message: {
            Text("Steps you finished still count toward your real times.")
        }
    }

    private var topBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(run.routineName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                Text("Leave at \(Format.time(run.leaveAt))")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondary)
            }
            Spacer()
            Button {
                confirmEnd = true
            } label: {
                Image(systemName: "xmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.secondary)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("End routine")
        }
        .padding(.top, 8)
    }

    private func stepFace(now: Date) -> some View {
        let status = run.status(now: now)
        let remaining = run.stepEndsAt.timeIntervalSince(now)
        return VStack(spacing: 20) {
            StepProgress(count: run.steps.count, current: run.stepIndex)
            Text("Step \(run.stepIndex + 1) of \(run.steps.count)")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.secondary)
            Text(run.currentStep?.name ?? "")
                .font(.system(size: 40, weight: .bold))
                .foregroundStyle(Theme.ink)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.6)
                .lineLimit(2)
            VStack(spacing: 4) {
                Text(Self.clock(remaining))
                    .font(.system(size: 76, weight: .semibold).monospacedDigit())
                    .foregroundStyle(remaining >= 0 ? Theme.ink : Theme.color(for: status))
                    .contentTransition(.numericText())
                Text(remaining >= 0 ? "left for this step" : "over this step's time")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondary)
            }
            .accessibilityElement(children: .combine)
            StatusPill(status: status)
            if let next = run.nextStep {
                Text("Then: \(next.name)")
                    .font(.body)
                    .foregroundStyle(Theme.secondary)
            } else {
                Text("Then: shoes on and out the door")
                    .font(.body)
                    .foregroundStyle(Theme.secondary)
            }
        }
    }

    private func leaving(now: Date) -> some View {
        let untilLeave = run.leaveAt.timeIntervalSince(now)
        return VStack(spacing: 20) {
            Image(systemName: "door.left.hand.open")
                .font(.system(size: 56, weight: .regular))
                .foregroundStyle(Theme.ink)
                .accessibilityHidden(true)
            Text(untilLeave > 0 ? "Ready. Head out\nby \(Format.time(run.leaveAt))." : "Time to go.")
                .font(.system(size: 36, weight: .bold))
                .foregroundStyle(Theme.ink)
                .multilineTextAlignment(.center)
            Text(untilLeave > 0 ? "\(Self.clock(untilLeave)) to spare" : "\(Self.clock(untilLeave)) past your leave time")
                .font(.title3.monospacedDigit().weight(.semibold))
                .foregroundStyle(untilLeave > 0 ? Theme.onTrack : Theme.late)
        }
    }

    private var controls: some View {
        VStack(spacing: 4) {
            if run.isLeaving {
                Button("I'm out the door") { store.finishRun() }
                    .buttonStyle(.primary)
                Color.clear.frame(height: 44)
            } else {
                Button("Done") { store.completeStep() }
                    .buttonStyle(.primary)
                Button("Skip this step") { store.skipStep() }
                    .buttonStyle(.secondary)
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

private struct StepProgress: View {
    let count: Int
    let current: Int

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<count, id: \.self) { index in
                Capsule()
                    .fill(index < current ? Theme.ink : index == current ? Theme.ink.opacity(0.45) : Theme.hairline)
                    .frame(height: 4)
            }
        }
        .accessibilityHidden(true)
    }
}

/// How the run went: when they left against the target, and each step's real
/// time against the guess.
private struct SummaryScreen: View {
    @EnvironmentObject private var store: RoutineStore
    @EnvironmentObject private var review: ReviewPromptService
    let finished: FinishedRun

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(headline)
                            .font(.largeTitle.bold())
                            .foregroundStyle(Theme.ink)
                        Text("Out the door at \(Format.time(finished.departure.left)), aiming for \(Format.time(finished.departure.target)).")
                            .font(.title3)
                            .foregroundStyle(Theme.secondary)
                    }
                    .padding(.top, 32)
                    Card {
                        VStack(alignment: .leading, spacing: 0) {
                            HStack {
                                SectionLabel("Step")
                                Spacer()
                                SectionLabel("Guess")
                                    .frame(width: 64, alignment: .trailing)
                                SectionLabel("Took")
                                    .frame(width: 64, alignment: .trailing)
                            }
                            .padding(.bottom, 6)
                            ForEach(finished.run.steps) { step in
                                Divider().overlay(Theme.hairline)
                                HStack {
                                    Text(step.name)
                                        .foregroundStyle(Theme.ink)
                                    Spacer()
                                    Text("\(step.guessMinutes) min")
                                        .foregroundStyle(Theme.secondary)
                                        .frame(width: 64, alignment: .trailing)
                                    Text(took(step))
                                        .fontWeight(.semibold)
                                        .foregroundStyle(Theme.ink)
                                        .frame(width: 64, alignment: .trailing)
                                }
                                .font(.subheadline.monospacedDigit())
                                .padding(.vertical, 10)
                            }
                        }
                        .padding(20)
                    }
                    Text("Tomorrow's plan already uses these times.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondary)
                }
                .padding(.horizontal, 24)
            }
            Button("Done") { store.dismissSummary() }
                .buttonStyle(.primary)
                .padding(.horizontal, 24)
                .padding(.bottom, 12)
        }
        .onAppear {
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

    private func took(_ step: RunStep) -> String {
        if step.skipped { return "Skipped" }
        guard let seconds = step.actualSeconds else { return "·" }
        return "\(Format.minutes(fromSeconds: seconds)) min"
    }
}
