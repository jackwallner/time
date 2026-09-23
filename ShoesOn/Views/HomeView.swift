import SwiftUI

/// The next departure, the real plan behind it, and how recent mornings went.
struct HomeView: View {
    @EnvironmentObject private var store: RoutineStore
    @EnvironmentObject private var purchases: StoreService

    @State private var editing: Routine?
    @State private var showSettings = false
    @State private var showPaywall = false

    var body: some View {
        NavigationStack {
            Group {
                if let routine = store.selectedRoutine {
                    RoutineDashboard(routine: routine) { editing = routine }
                } else {
                    emptyState
                }
            }
            .background(Theme.background.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { routineMenu }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Settings")
                }
            }
            .tint(Theme.ink)
        }
        .sheet(item: $editing) { routine in
            RoutineEditorView(routine: routine, isNew: store.routine(id: routine.id) == nil)
        }
        .sheet(isPresented: $showSettings) { SettingsView() }
        .sheet(isPresented: $showPaywall) { PaywallView(surface: "shoeson_new_routine") }
    }

    private var routineMenu: some View {
        Menu {
            ForEach(store.routines) { routine in
                Button {
                    store.select(routine.id)
                } label: {
                    if routine.id == store.selectedRoutine?.id {
                        Label(routine.name, systemImage: "checkmark")
                    } else {
                        Text(routine.name)
                    }
                }
            }
            Divider()
            Button {
                newRoutine()
            } label: {
                Label(purchases.isPro || store.routines.isEmpty ? "New routine" : "New routine (Pro)", systemImage: "plus")
            }
        } label: {
            HStack(spacing: 5) {
                Text(store.selectedRoutine?.name ?? "Shoes On")
                    .font(.headline)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.heavy))
            }
            .foregroundStyle(Theme.ink)
        }
        .accessibilityLabel("Routines")
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Text("No routine yet")
                .font(.title2.bold())
            Button("Create a routine", action: newRoutine)
                .buttonStyle(.primary)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func newRoutine() {
        guard store.routines.isEmpty || purchases.isPro else {
            showPaywall = true
            return
        }
        editing = Routine(
            name: "",
            leaveHour: 9,
            leaveMinute: 0,
            weekdays: [1, 7],
            steps: [RoutineStep(name: "Get dressed", guessMinutes: 10), RoutineStep(name: "Shoes, keys, out", guessMinutes: 5)]
        )
    }
}

private struct RoutineDashboard: View {
    @EnvironmentObject private var store: RoutineStore
    let routine: Routine
    let onEdit: () -> Void

    var body: some View {
        TimelineView(.everyMinute) { context in
            let now = AppClock.adjust(context.date)
            let plan = store.nextPlan(for: routine, now: now)
                ?? store.plan(for: routine, leaveAt: routine.leaveTimeForRunStarted(at: now))
            ScrollView {
                VStack(spacing: 14) {
                    NextDepartureCard(routine: routine, plan: plan, isScheduled: !routine.weekdays.isEmpty, now: now) {
                        withAnimation(.smooth) { store.startRun(routineID: routine.id) }
                    }
                    Card {
                        HStack {
                            SectionLabel("The real plan")
                            Spacer()
                            Button("Edit", action: onEdit)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Theme.ink)
                        }
                        .padding(.bottom, 16)
                        PlanTimeline(plan: plan)
                    }
                    RecordCard(departures: store.departures(for: routine.id), calibration: store.calibration)
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 32)
            }
        }
    }
}

private struct NextDepartureCard: View {
    let routine: Routine
    let plan: DeparturePlan
    let isScheduled: Bool
    let now: Date
    let onStart: () -> Void

    var body: some View {
        let total = plan.realMinutes + plan.headStartMinutes
        Card(padding: 22) {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    SectionLabel(isScheduled ? "\(Format.day(plan.leaveAt, now: now)) · \(Format.weekdays(routine.weekdays))" : "Any day")
                    Text("Start \(Format.time(plan.alertAt))")
                        .font(.system(size: 44, weight: .heavy, design: .rounded))
                        .foregroundStyle(Theme.ink)
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Theme.secondary)
                }
                GapBars(guess: plan.guessMinutes, real: total)
                if total > plan.guessMinutes {
                    HStack(spacing: 8) {
                        Circle().fill(Theme.gap).frame(width: 8, height: 8)
                        Text("\(Format.duration(minutes: total - plan.guessMinutes)) your guess leaves out")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Theme.ink)
                    }
                }
                Button(action: onStart) {
                    Label("Start now", systemImage: "play.fill")
                }
                .buttonStyle(.primary)
            }
        }
    }

    private var subtitle: String {
        let leave = "Out the door \(Format.time(plan.leaveAt))"
        guard plan.alertAt > now else { return "\(leave) · already on the clock" }
        return "\(leave) · starts \(Format.relative(to: plan.alertAt, now: now))"
    }
}

private struct RecordCard: View {
    let departures: [DepartureRecord]
    let calibration: Calibration

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 16) {
                SectionLabel("How it's going")
                if departures.isEmpty {
                    Text("Your first run starts the learning. Tap Done as you finish each step and Shoes On times it for you.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    let recent = Array(departures.prefix(7))
                    let onTime = recent.filter(\.wasOnTime).count
                    HStack(alignment: .lastTextBaseline, spacing: 6) {
                        Text("\(onTime)")
                            .font(.system(size: 44, weight: .heavy, design: .rounded))
                            .foregroundStyle(Theme.ink)
                        Text("of \(recent.count) on time")
                            .font(.headline)
                            .foregroundStyle(Theme.secondary)
                        Spacer()
                    }
                    LatenessStrip(records: recent.reversed())
                }
                Divider().overlay(Theme.hairline)
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Your pace")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.ink)
                        Text(paceText)
                            .font(.footnote)
                            .foregroundStyle(Theme.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 12)
                    Text(Format.multiplier(calibration.pace))
                        .font(.system(.title2, design: .rounded).weight(.heavy))
                        .foregroundStyle(Theme.ink)
                }
            }
        }
    }

    private var paceText: String {
        let count = calibration.pacedStepCount
        let sentence = Format.paceSentence(calibration.pace)
        if count == 0 { return "Until it has your real times, steps take \(sentence)." }
        return "From \(count) timed \(count == 1 ? "step" : "steps"): things take \(sentence)."
    }
}

/// Recent departures as bars around the leave-time line: up for late, down
/// for early.
private struct LatenessStrip: View {
    let records: [DepartureRecord]

    var body: some View {
        let maxMinutes = max(5, records.map { abs($0.lateSeconds) / 60 }.max() ?? 5)
        HStack(alignment: .center, spacing: 8) {
            ForEach(records) { record in
                let minutes = record.lateSeconds / 60
                let height = max(4, CGFloat(abs(minutes) / maxMinutes) * 26)
                VStack(spacing: 4) {
                    ZStack {
                        Color.clear.frame(height: 56)
                        Capsule()
                            .fill(record.wasOnTime ? Theme.onTrack : Theme.behind)
                            .frame(width: 10, height: height)
                            .offset(y: minutes > 0 ? -height / 2 : height / 2)
                    }
                    Text(record.left.formatted(.dateTime.weekday(.narrow)))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Theme.secondary)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .overlay(alignment: .top) {
            Rectangle().fill(Theme.hairline).frame(height: 1).offset(y: 28)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(records.map { Format.lateness(seconds: $0.lateSeconds) }.joined(separator: ", "))
    }
}
