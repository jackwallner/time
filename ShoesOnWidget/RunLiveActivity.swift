import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

@main
struct ShoesOnWidgetBundle: WidgetBundle {
    var body: some Widget {
        RunLiveActivity()
    }
}

/// Lock screen and Dynamic Island for a run: the step, its clock, the leave
/// time, whether it's on schedule, and a Done button.
struct RunLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RunActivityAttributes.self) { context in
            LockScreenRun(state: context.state, isStale: context.isStale)
                .activityBackgroundTint(Color(red: 0.07, green: 0.075, blue: 0.08))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            let state = context.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title(state))
                            .font(.headline)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        Text("Leave \(Format.time(state.leaveAt))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    countdown(state)
                        .font(.title2.weight(.semibold).monospacedDigit())
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 90, alignment: .trailing)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        statusText(state, isStale: context.isStale)
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        doneButton(state)
                    }
                    .padding(.horizontal, 4)
                }
            } compactLeading: {
                Image(systemName: state.isLeaving ? "door.left.hand.open" : "figure.walk")
                    .foregroundStyle(statusColor(state, isStale: context.isStale))
            } compactTrailing: {
                countdown(state)
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .frame(maxWidth: 52)
            } minimal: {
                Image(systemName: "figure.walk")
                    .foregroundStyle(statusColor(state, isStale: context.isStale))
            }
        }
    }
}

private struct LockScreenRun: View {
    let state: RunSnapshot
    let isStale: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            ring
                .frame(width: 64, height: 64)
            VStack(alignment: .leading, spacing: 3) {
                Text(state.isLeaving ? "Out the door \(Format.time(state.leaveAt))" : "Step \(state.stepIndex + 1) of \(state.stepCount) · out \(Format.time(state.leaveAt))")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(1)
                Text(title(state))
                    .font(.system(.title3, design: .rounded).weight(.heavy))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                statusText(state, isStale: isStale)
                    .font(.system(.subheadline, design: .rounded).weight(.bold))
                if let next = state.nextStepName, !state.isLeaving {
                    Text("Then \(next)")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.55))
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            doneButton(state)
        }
        .padding(16)
    }

    /// The step's clock as a ring that empties, with the countdown inside.
    private var ring: some View {
        ZStack {
            if state.isLeaving {
                Circle().stroke(Theme.onTrack, lineWidth: 6)
                Image(systemName: "door.left.hand.open")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
            } else {
                ProgressView(
                    timerInterval: state.stepStartedAt...max(state.stepEndsAt, state.stepStartedAt.addingTimeInterval(1)),
                    countsDown: true
                ) {
                    EmptyView()
                } currentValueLabel: {
                    EmptyView()
                }
                .progressViewStyle(.circular)
                .tint(statusColor(state, isStale: isStale))
                countdown(state)
                    .font(.system(size: 14, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .frame(width: 50)
            }
        }
    }
}

private func title(_ state: RunSnapshot) -> String {
    state.isLeaving ? "Shoes on, head out" : (state.stepName ?? "")
}

/// Counts down to the end of the step, or to the leave time once ready.
@ViewBuilder
private func countdown(_ state: RunSnapshot) -> some View {
    let target = state.isLeaving ? state.leaveAt : state.stepEndsAt
    if target > .now {
        Text(timerInterval: Date.now...target, countsDown: true)
    } else {
        Text("Now")
    }
}

/// The status as of the last update. Once the step's time is up the snapshot
/// is stale, and the only honest thing to say is that it is running over.
private func statusText(_ state: RunSnapshot, isStale: Bool) -> some View {
    let text: String
    if isStale && !state.isLeaving {
        text = "Running over"
    } else if isStale {
        text = "Time to go"
    } else {
        text = state.status(now: .now).label
    }
    return Text(text).foregroundStyle(statusColor(state, isStale: isStale))
}

private func statusColor(_ state: RunSnapshot, isStale: Bool) -> Color {
    if isStale { return Theme.behind }
    return Theme.color(for: state.status(now: .now))
}

private func doneButton(_ state: RunSnapshot) -> some View {
    Button(intent: CompleteStepIntent()) {
        Text(state.isLeaving ? "I'm out" : "Done")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.black)
            .padding(.horizontal, 18)
            .padding(.vertical, 8)
            .background(.white, in: Capsule())
    }
    .buttonStyle(.plain)
}
