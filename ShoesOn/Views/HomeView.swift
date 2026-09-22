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
            .toolbarBackground(Theme.background, for: .navigationBar)
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
                Label("New routine", systemImage: "plus")
            }
        } label: {
            HStack(spacing: 4) {
                Text(store.selectedRoutine?.name ?? "Shoes On")
                    .font(.headline)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.bold))
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
            let now = context.date
            let plan = store.nextPlan(for: routine, now: now)
                ?? store.plan(for: routine, leaveAt: routine.leaveTimeForRunStarted(at: now))
            ScrollView {
                VStack(spacing: 16) {
                    NextDepartureCard(routine: routine, plan: plan, isScheduled: !routine.weekdays.isEmpty, now: now) {
                        store.startRun(routineID: routine.id)
                    }
                    PlanCard(plan: plan, onEdit: onEdit)
                    RecordCard(departures: store.departures(for: routine.id), calibration: store.calibration)
                }
                .padding(.horizontal, Theme.margin)
                .padding(.bottom, 24)
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
        Card {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    SectionLabel(isScheduled ? "\(Format.day(plan.leaveAt, now: now)) · \(Format.weekdays(routine.weekdays))" : "Any day")
                    Text("Start at \(Format.time(plan.alertAt))")
                        .font(.system(.largeTitle, design: .default).weight(.bold))
                        .foregroundStyle(Theme.ink)
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.body)
                        .foregroundStyle(Theme.secondary)
                }
                Button("Start now", action: onStart)
                    .buttonStyle(.primary)
            }
            .padding(20)
        }
    }

    private var subtitle: String {
        let leave = "Leave at \(Format.time(plan.leaveAt))"
        guard plan.alertAt > now else { return "\(leave). You're already on the clock." }
        return "\(leave) · starts \(Format.relative(to: plan.alertAt, now: now))"
    }
}

private struct PlanCard: View {
    let plan: DeparturePlan
    let onEdit: () -> Void

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    SectionLabel("The real plan")
                    Spacer()
                    Button("Edit", action: onEdit)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.ink)
                }
                .padding(.bottom, 4)
                if plan.headStartMinutes > 0 {
                    headStartRow
                    Divider().overlay(Theme.hairline)
                }
                ForEach(plan.steps) { planned in
                    PlanStepRow(planned: planned)
                    Divider().overlay(Theme.hairline)
                }
                HStack(alignment: .firstTextBaseline) {
                    Text(Format.time(plan.leaveAt))
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(Theme.secondary)
                        .frame(minWidth: 64, alignment: .leading)
                    Text("Out the door")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Theme.ink)
                    Spacer()
                }
                .padding(.vertical, 12)
                summary
                    .padding(.top, 4)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
    }

    private var headStartRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(Format.time(plan.alertAt))
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(Theme.secondary)
                .frame(minWidth: 64, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text("Get going")
                    .foregroundStyle(Theme.ink)
                Text("You usually start a few minutes after the alert")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondary)
            }
            Spacer(minLength: 8)
            Text(Format.duration(minutes: plan.headStartMinutes))
                .font(.body.monospacedDigit().weight(.semibold))
                .foregroundStyle(Theme.ink)
        }
        .padding(.vertical, 12)
    }

    private var summary: some View {
        let total = plan.realMinutes + plan.headStartMinutes
        let hidden = plan.hiddenMinutes
        return Text(hidden > 0
            ? "You'd guess \(Format.duration(minutes: plan.guessMinutes)). It really takes \(Format.duration(minutes: total)), so trusting the guess would make you \(Format.duration(minutes: hidden)) late."
            : "You'd guess \(Format.duration(minutes: plan.guessMinutes)), and it really takes \(Format.duration(minutes: total)).")
            .font(.footnote)
            .foregroundStyle(Theme.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct RecordCard: View {
    let departures: [DepartureRecord]
    let calibration: Calibration

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                SectionLabel("How it's going")
                if departures.isEmpty {
                    Text("Your first run starts the learning. Tap Done as you finish each step, and Shoes On times them for you.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    let recent = Array(departures.prefix(7))
                    let onTime = recent.filter(\.wasOnTime).count
                    HStack(alignment: .firstTextBaseline) {
                        Text("On time \(onTime) of \(recent.count)")
                            .font(.title3.bold())
                            .foregroundStyle(Theme.ink)
                        Spacer()
                        HStack(spacing: 5) {
                            ForEach(recent.reversed()) { record in
                                Circle()
                                    .fill(record.wasOnTime ? Theme.onTrack : Theme.behind)
                                    .frame(width: 10, height: 10)
                            }
                        }
                        .accessibilityHidden(true)
                    }
                    VStack(spacing: 0) {
                        ForEach(recent.prefix(3)) { record in
                            HStack {
                                Text(record.left.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
                                    .foregroundStyle(Theme.secondary)
                                Spacer()
                                Text("Left \(Format.time(record.left))")
                                    .foregroundStyle(Theme.ink)
                                Text(Format.lateness(seconds: record.lateSeconds))
                                    .foregroundStyle(record.wasOnTime ? Theme.onTrack : Theme.behind)
                                    .frame(minWidth: 88, alignment: .trailing)
                            }
                            .font(.subheadline.monospacedDigit())
                            .padding(.vertical, 6)
                        }
                    }
                }
                Divider().overlay(Theme.hairline)
                Text(paceText)
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(20)
        }
    }

    private var paceText: String {
        let count = calibration.pacedStepCount
        let sentence = Format.paceSentence(calibration.pace)
        if count == 0 { return "Until it has your real times, Shoes On assumes steps take \(sentence)." }
        return "From \(count) timed \(count == 1 ? "step" : "steps"), things take you \(sentence)."
    }
}
