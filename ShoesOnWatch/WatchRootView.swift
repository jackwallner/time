import SwiftUI

struct WatchRootView: View {
    @EnvironmentObject private var model: WatchModel

    var body: some View {
        NavigationStack {
            Group {
                if let payload = model.payload {
                    if !payload.isPro {
                        locked
                    } else if let run = payload.run {
                        WatchRunView(run: run)
                    } else {
                        idle(payload.next)
                    }
                } else {
                    message("Set up a routine in Shoes On on your iPhone.")
                }
            }
        }
    }

    private var locked: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: "applewatch")
                    .font(.title2)
                Text("Watch coach")
                    .font(.headline)
                Text("The Apple Watch coach is part of Shoes On Pro. Unlock it in the iPhone app, under Settings.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func idle(_ next: NextDepartureSnapshot?) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if let next {
                    Text(next.routineName)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Text("Start \(Format.time(next.alertAt))")
                        .font(.title3.weight(.bold))
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                    Text("Leave \(Format.time(next.leaveAt)) · \(Format.day(next.leaveAt))")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    Text("No departure scheduled.")
                        .font(.headline)
                }
                Button("Start now") { model.send(.start) }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.onTrack)
                    .disabled(model.isSending)
                    .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func message(_ text: String) -> some View {
        Text(text)
            .font(.footnote)
            .multilineTextAlignment(.center)
            .foregroundStyle(.secondary)
            .padding()
    }
}

private struct WatchRunView: View {
    @EnvironmentObject private var model: WatchModel
    let run: RunSnapshot

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let now = context.date
            let status = run.status(now: now)
            VStack(alignment: .leading, spacing: 4) {
                Text(run.isLeaving ? "Out the door" : "Step \(run.stepIndex + 1) of \(run.stepCount)")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(run.isLeaving ? "Shoes on" : (run.stepName ?? ""))
                    .font(.title3.weight(.bold))
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                HStack(spacing: 10) {
                    ring(now: now, status: status)
                        .frame(width: 30, height: 30)
                    Text(clock(run.isLeaving ? run.leaveAt : run.stepEndsAt, now: now))
                        .font(.system(size: 34, weight: .semibold, design: .rounded).monospacedDigit())
                        .foregroundStyle(clockColor(now: now, status: status))
                }
                Text(status.label)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.color(for: status))
                Spacer(minLength: 2)
                Button(run.isLeaving ? "I'm out" : "Done") {
                    model.send(run.isLeaving ? .leave : .completeStep)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.onTrack)
                .disabled(model.isSending)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .toolbar {
            if !run.isLeaving {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        model.send(.skipStep)
                    } label: {
                        Image(systemName: "forward.end")
                    }
                    .accessibilityLabel("Skip step")
                }
            }
        }
    }

    /// The step's time as a ring that empties, like the phone's dial.
    private func ring(now: Date, status: RunStatus) -> some View {
        let total = max(run.stepEndsAt.timeIntervalSince(run.stepStartedAt), 1)
        let left = run.isLeaving ? 1 : min(max(run.stepEndsAt.timeIntervalSince(now) / total, 0), 1)
        return ZStack {
            Circle().stroke(Color.white.opacity(0.15), lineWidth: 4)
            Circle()
                .trim(from: 0, to: max(left, 0.001))
                .stroke(Theme.color(for: status), style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }

    private func clock(_ target: Date, now: Date) -> String {
        let seconds = target.timeIntervalSince(now)
        let total = Int(abs(seconds).rounded(.down))
        let text = String(format: "%d:%02d", total / 60, total % 60)
        return seconds < 0 ? "+\(text)" : text
    }

    private func clockColor(now: Date, status: RunStatus) -> Color {
        let target = run.isLeaving ? run.leaveAt : run.stepEndsAt
        return target >= now ? .white : Theme.color(for: status)
    }
}
