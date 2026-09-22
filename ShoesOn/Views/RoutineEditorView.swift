import SwiftUI

/// Name, leave time, days, and the steps with their guesses.
struct RoutineEditorView: View {
    @EnvironmentObject private var store: RoutineStore
    @Environment(\.dismiss) private var dismiss

    @State private var routine: Routine
    @State private var leaveTime: Date
    @State private var newStepName = ""
    @State private var confirmDelete = false
    let isNew: Bool

    init(routine: Routine, isNew: Bool) {
        _routine = State(initialValue: routine)
        _leaveTime = State(initialValue: routine.leaveTime(on: .now))
        self.isNew = isNew
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name, like Weekday mornings", text: $routine.name)
                    DatePicker("Leave at", selection: $leaveTime, displayedComponents: .hourAndMinute)
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Days")
                        WeekdayPicker(selection: $routine.weekdays)
                    }
                    .padding(.vertical, 4)
                } footer: {
                    Text(routine.weekdays.isEmpty
                        ? "With no days set, there are no alerts. You can still start it by hand."
                        : "Alerts come on these days. You can start it by hand any day.")
                }

                Section {
                    ForEach($routine.steps) { $step in
                        HStack(spacing: 12) {
                            TextField("Step", text: $step.name, axis: .vertical)
                                .lineLimit(1...3)
                            MinuteStepper(minutes: $step.guessMinutes)
                        }
                    }
                    .onDelete { routine.steps.remove(atOffsets: $0) }
                    .onMove { routine.steps.move(fromOffsets: $0, toOffset: $1) }
                    HStack {
                        TextField("Add a step", text: $newStepName)
                            .submitLabel(.done)
                            .onSubmit(addStep)
                        Button("Add", action: addStep)
                            .disabled(newStepName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                } header: {
                    Text("Steps, in order")
                } footer: {
                    Text("Minutes are your guess. Shoes On keeps it, and plans with your real times once it has them.")
                }

                if !isNew && store.routines.count > 1 {
                    Section {
                        Button("Delete routine", role: .destructive) { confirmDelete = true }
                    }
                }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle(isNew ? "New routine" : "Edit routine")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(!canSave)
                }
            }
            .confirmationDialog("Delete \(routine.name)?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    store.delete(routine.id)
                    dismiss()
                }
            } message: {
                Text("Its steps and timing history go with it.")
            }
        }
        .tint(Theme.ink)
    }

    private var canSave: Bool {
        !routine.name.trimmingCharacters(in: .whitespaces).isEmpty
            && !routine.steps.isEmpty
            && routine.steps.allSatisfy { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    private func addStep() {
        let name = newStepName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        routine.steps.append(RoutineStep(name: name, guessMinutes: 10))
        newStepName = ""
    }

    private func save() {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: leaveTime)
        routine.leaveHour = parts.hour ?? routine.leaveHour
        routine.leaveMinute = parts.minute ?? routine.leaveMinute
        routine.name = routine.name.trimmingCharacters(in: .whitespaces)
        store.save(routine)
        dismiss()
    }
}
