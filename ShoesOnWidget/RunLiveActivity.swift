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
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(state.isLeaving ? "Out the door" : "Step \(state.stepIndex + 1) of \(state.stepCount)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.6))
                Spacer()
                Text("Leave \(Format.time(state.leaveAt))")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.6))
            }
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title(state))
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    statusText(state, isStale: isStale)
                        .font(.subheadline.weight(.semibold))
                }
                Spacer(minLength: 8)
                countdown(state)
                    .font(.system(size: 34, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 120, alignment: .trailing)
            }
            if !state.isLeaving {
                ProgressView(timerInterval: state.stepStartedAt...max(state.stepEndsAt, state.stepStartedAt.addingTimeInterval(1)), countsDown: false) {
                    EmptyView()
                } currentValueLabel: {
                    EmptyView()
                }
                .tint(statusColor(state, isStale: isStale))
            }
            HStack {
                if let next = state.nextStepName, !state.isLeaving {
                    Text("Then: \(next)")
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)
                }
                Spacer()
                doneButton(state)
            }
        }
        .padding(16)
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
