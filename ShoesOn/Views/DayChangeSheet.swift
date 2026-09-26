import SwiftUI

/// One day, just this once: leave at another time, or skip it. The plan for
/// that day is worked out as the time moves, so the start time is never a
/// guess either.
struct DayChangeSheet: View {
    @EnvironmentObject private var store: RoutineStore
    @Environment(\.dismiss) private var dismiss

    let routine: Routine
    @State private var day: Date
    @State private var skip: Bool
    @State private var time: Date

    private let calendar = Calendar.current

    init(routine: Routine, day: Date) {
        self.routine = routine
        let start = Calendar.current.startOfDay(for: day)
        _day = State(initialValue: start)
        _skip = State(initialValue: routine.change(on: start)?.isSkip ?? false)
        _time = State(initialValue: routine.leaveTime(on: start))
    }

    var body: some View {
        let now = AppClock.now
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    dayStrip(now: now)
                    if isScheduled {
                        Picker("Change", selection: $skip.animation(.smooth)) {
                            Text("Another time").tag(false)
                            Text("Skip it").tag(true)
                        }
                        .pickerStyle(.segmented)
                    }
                    if !skip || !isScheduled {
                        DatePicker("Leave at", selection: $time, displayedComponents: .hourAndMinute)
                            .datePickerStyle(.wheel)
                            .labelsHidden()
                            .frame(maxWidth: .infinity)
                    }
                    preview(now: now)
                }
                .padding(.horizontal, 24)
                .padding(.top, 8)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) { actions(now: now) }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Just this once")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .tint(Theme.ink)
        .presentationDragIndicator(.visible)
    }

    // MARK: - Pieces

    private var isScheduled: Bool { routine.weekdays.contains(calendar.component(.weekday, from: day)) }

    private var leaveAt: Date {
        let parts = calendar.dateComponents([.hour, .minute], from: time)
        return calendar.date(bySettingHour: parts.hour ?? 0, minute: parts.minute ?? 0, second: 0, of: day) ?? day
    }

    private var isSkipping: Bool { skip && isScheduled }

    private func dayStrip(now: Date) -> some View {
        let today = calendar.startOfDay(for: now)
        let days = (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: today) }
        return HStack(spacing: 6) {
            ForEach(days, id: \.self) { date in
                let isOn = calendar.isDate(date, inSameDayAs: day)
                let departs = routine.departs(on: date)
                Button {
                    withAnimation(.snappy) { select(date) }
                } label: {
                    VStack(spacing: 4) {
                        Text(date.formatted(.dateTime.weekday(.abbreviated)))
                            .font(.caption2.weight(.bold))
                            .textCase(.uppercase)
                        Text(date.formatted(.dateTime.day()))
                            .font(.headline.monospacedDigit())
                        Circle()
                            .fill(departs ? (isOn ? Theme.inkInverse : Theme.ink) : .clear)
                            .frame(width: 5, height: 5)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .foregroundStyle(isOn ? Theme.inkInverse : Theme.ink)
                    .background(isOn ? Theme.ink : Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(Theme.hairline, lineWidth: isOn ? 0 : 1)
                    )
                }
                .buttonStyle(.plain)
                .sensoryFeedback(.selection, trigger: isOn)
                .accessibilityLabel(date.formatted(.dateTime.weekday(.wide).day().month()))
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
    }

    @ViewBuilder private func preview(now: Date) -> some View {
        Card {
            if isSkipping {
                Text("No alerts \(Format.dayPhrase(day, now: now)).")
                    .font(.system(.title2, design: .rounded).weight(.heavy))
                    .foregroundStyle(Theme.ink)
                Text("\(routine.name) is back to normal the day after.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondary)
                    .padding(.top, 4)
            } else if leaveAt <= now {
                Text("That time has already passed.")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.late)
            } else {
                let plan = store.plan(for: routine, leaveAt: leaveAt)
                SectionLabel(Format.day(day, now: now))
                    .padding(.bottom, 8)
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Start")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Theme.secondary)
                        Text(Format.time(plan.alertAt))
                            .font(.system(.title, design: .rounded).weight(.heavy))
                            .foregroundStyle(Theme.ink)
                            .contentTransition(.numericText())
                    }
                    Spacer()
                    Image(systemName: "arrow.right")
                        .font(.body.weight(.bold))
                        .foregroundStyle(Theme.secondary)
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Out the door")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Theme.secondary)
                        Text(Format.time(plan.leaveAt))
                            .font(.system(.title, design: .rounded).weight(.heavy))
                            .foregroundStyle(Theme.onTrack)
                            .contentTransition(.numericText())
                    }
                }
                .animation(.snappy, value: plan.leaveAt)
            }
        }
    }

    private func actions(now: Date) -> some View {
        let hasChange = routine.change(on: day) != nil
        return VStack(spacing: 4) {
            Button("Save", action: save)
                .buttonStyle(.primary)
                .disabled(!isSkipping && leaveAt <= now)
            Button("Back to normal") {
                store.setChange(nil, on: day, routineID: routine.id)
                dismiss()
            }
            .buttonStyle(.secondary)
            .opacity(hasChange ? 1 : 0)
            .disabled(!hasChange)
        }
        .padding(.horizontal, 24)
        .padding(.top, 10)
        .background(Theme.background)
    }

    // MARK: - Actions

    private func select(_ date: Date) {
        day = calendar.startOfDay(for: date)
        skip = routine.change(on: day)?.isSkip ?? false
        time = routine.leaveTime(on: day)
    }

    private func save() {
        let change: DayChange
        if isSkipping {
            change = DayChange(day: day, leaveMinuteOfDay: nil)
        } else {
            let parts = calendar.dateComponents([.hour, .minute], from: time)
            change = DayChange(day: day, leaveMinuteOfDay: (parts.hour ?? 0) * 60 + (parts.minute ?? 0))
        }
        store.setChange(change, on: day, routineID: routine.id)
        dismiss()
    }
}
