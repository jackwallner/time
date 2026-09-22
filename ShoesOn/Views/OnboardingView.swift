import SwiftUI

/// Six pages: what it does, the pace question, the leave time, the steps, the
/// reveal of the real plan, and the one-time Pro offer. The primary button
/// sits in exactly the same frame on every page.
struct OnboardingView: View {
    @EnvironmentObject private var store: RoutineStore
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var purchases: StoreService

    @State private var page: Int
    @State private var pace: PaceAnswer?
    @State private var leaveTime: Date
    @State private var weekdays: Set<Int> = [2, 3, 4, 5, 6]
    @State private var drafts: [StepDraft] = StepDraft.presets
    @State private var customName = ""
    @State private var isAdvancing = false

    private static let pageCount = 6

    init(startPage: Int = 0) {
        _page = State(initialValue: startPage)
        _leaveTime = State(initialValue: Calendar.current.date(bySettingHour: 8, minute: 15, second: 0, of: .now) ?? .now)
        if startPage > 1 { _pace = State(initialValue: .halfOver) }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                content
                    .padding(.horizontal, 24)
                    .padding(.top, 8)
                    .padding(.bottom, 24)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollDismissesKeyboard(.interactively)
            .scrollBounceBehavior(.basedOnSize)
        }
        .background(Theme.background.ignoresSafeArea())
        .safeAreaInset(edge: .bottom, spacing: 0) { bottomBar }
        .animation(.easeInOut(duration: 0.25), value: page)
        .onChange(of: page) { _, newPage in
            if newPage == Self.pageCount - 1 {
                purchases.trackPaywallImpression(id: "shoeson_onboarding_pro")
            }
        }
    }

    // MARK: - Chrome

    private var header: some View {
        HStack {
            Button {
                page -= 1
            } label: {
                Image(systemName: "chevron.left")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Back")
            .opacity(page > 0 && page < Self.pageCount - 1 ? 1 : 0)
            .disabled(page == 0 || page == Self.pageCount - 1)
            Spacer()
        }
        .padding(.horizontal, 12)
        .frame(height: 44)
    }

    private var bottomBar: some View {
        OnboardingBottomBar(
            primaryTitle: primaryTitle,
            isBusy: isAdvancing || (isPitch && purchases.isPurchasing),
            isDisabled: !canContinue,
            primaryAction: advance,
            footer: OnboardingLegalFooter(isPlaceholder: !isPitch, isRestoring: purchases.isPurchasing) {
                Task {
                    await purchases.restore()
                    if purchases.isPro { finish() }
                }
            }
        ) {
            VStack(spacing: 8) {
                if isPitch {
                    if let message = purchases.errorMessage {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(Theme.late)
                            .multilineTextAlignment(.center)
                    }
                    Text(pitchDisclosure)
                        .font(.footnote)
                        .foregroundStyle(Theme.secondary)
                        .multilineTextAlignment(.center)
                    Button("Get Started", action: finish)
                        .buttonStyle(.secondary)
                } else {
                    PageDots(count: Self.pageCount - 1, current: page)
                        .padding(.bottom, 4)
                }
            }
        }
        .background(Theme.background)
    }

    private var isPitch: Bool { page == Self.pageCount - 1 }

    private var primaryTitle: String {
        isPitch ? "Unlock Pro" : "Continue"
    }

    private var pitchDisclosure: String {
        if let price = purchases.priceLabel {
            return "\(price), one-time purchase. No subscription."
        }
        return "One-time purchase. No subscription."
    }

    private var canContinue: Bool {
        switch page {
        case 1: pace != nil
        case 2: !weekdays.isEmpty
        case 3: drafts.contains { $0.isOn }
        case Self.pageCount - 1: purchases.lifetimePackage != nil || !purchases.isLoadingProducts
        default: true
        }
    }

    // MARK: - Pages

    @ViewBuilder private var content: some View {
        switch page {
        case 0: welcome
        case 1: pacePage
        case 2: leavePage
        case 3: stepsPage
        case 4: revealPage
        default: pitchPage
        }
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 20) {
            Image("OnboardingMark")
                .resizable()
                .scaledToFit()
                .frame(width: 88, height: 88)
                .padding(.top, 24)
                .accessibilityHidden(true)
            Text("Leave on time.\nFor real this time.")
                .font(.largeTitle.bold())
                .foregroundStyle(Theme.ink)
            Text("Tell Shoes On when you need to walk out the door. It works backward through your routine and tells you when to start.")
                .font(.title3)
                .foregroundStyle(Theme.secondary)
            Text("Then it learns how long each step really takes you, so the plan stops trusting your guesses.")
                .font(.title3)
                .foregroundStyle(Theme.secondary)
        }
    }

    private var pacePage: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("When getting ready feels like an hour, it usually takes…")
                .font(.title.bold())
                .foregroundStyle(Theme.ink)
            Text("Be honest. It only sets the starting point; your real times take over as you go.")
                .font(.body)
                .foregroundStyle(Theme.secondary)
            VStack(spacing: 10) {
                ForEach(PaceAnswer.allCases) { answer in
                    ChoiceRow(title: answer.title, detail: answer.detail, isSelected: pace == answer) {
                        pace = answer
                    }
                }
            }
        }
    }

    private var leavePage: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("When do you need to walk out the door?")
                .font(.title.bold())
                .foregroundStyle(Theme.ink)
            DatePicker("Leave at", selection: $leaveTime, displayedComponents: .hourAndMinute)
                .datePickerStyle(.wheel)
                .labelsHidden()
                .frame(maxWidth: .infinity)
            VStack(alignment: .leading, spacing: 10) {
                SectionLabel("On these days")
                WeekdayPicker(selection: $weekdays)
            }
        }
    }

    private var stepsPage: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("What happens before you leave?")
                .font(.title.bold())
                .foregroundStyle(Theme.ink)
            Text("Guess how long each takes. Being wrong is fine; that's what Shoes On is for.")
                .font(.body)
                .foregroundStyle(Theme.secondary)
            VStack(spacing: 0) {
                ForEach($drafts) { $draft in
                    StepDraftRow(draft: $draft)
                    if draft.id != drafts.last?.id {
                        Divider().overlay(Theme.hairline)
                    }
                }
                Divider().overlay(Theme.hairline)
                HStack {
                    TextField("Add your own step", text: $customName)
                        .submitLabel(.done)
                        .onSubmit(addCustom)
                    Button("Add", action: addCustom)
                        .font(.body.weight(.semibold))
                        .disabled(customName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .padding(.vertical, 14)
            }
            .padding(.horizontal, 16)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous).strokeBorder(Theme.hairline))
        }
    }

    private var revealPage: some View {
        let plan = draftPlan
        return VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Text("It really takes")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(Theme.secondary)
                Text(Format.duration(minutes: plan.realMinutes))
                    .font(.system(size: 52, weight: .bold))
                    .foregroundStyle(Theme.ink)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
            }
            GuessBars(guess: plan.guessMinutes, real: plan.realMinutes)
            Card {
                VStack(alignment: .leading, spacing: 6) {
                    SectionLabel("Your plan")
                    Text("Start at \(Format.time(plan.alertAt))")
                        .font(.title2.bold())
                        .foregroundStyle(Theme.ink)
                    Text("to walk out at \(Format.time(plan.leaveAt)).")
                        .font(.body)
                        .foregroundStyle(Theme.secondary)
                }
                .padding(20)
            }
            Text("Shoes On will nudge you at \(Format.time(plan.alertAt)), keep you on pace step by step, and replace these estimates with your real times as you use it.")
                .font(.body)
                .foregroundStyle(Theme.secondary)
        }
    }

    private var pitchPage: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Shoes On Pro")
                    .font(.largeTitle.bold())
                    .foregroundStyle(Theme.ink)
                Text("Your first routine is free for good. Pro adds the rest of your week.")
                    .font(.title3)
                    .foregroundStyle(Theme.secondary)
            }
            VStack(alignment: .leading, spacing: 20) {
                ProBenefit(symbol: "square.stack", title: "Every routine", detail: "Workdays, school runs, the gym, Sunday brunch. Each one learns its own times.")
                ProBenefit(symbol: "applewatch", title: "Apple Watch coach", detail: "The step you're on, the time left, and whether you're slipping. Tap Done from your wrist.")
                ProBenefit(symbol: "checkmark.seal", title: "Pay once", detail: "No subscription. It's yours.")
            }
        }
    }

    // MARK: - Actions

    private var draftRoutine: Routine {
        let calendar = Calendar.current
        let parts = calendar.dateComponents([.hour, .minute], from: leaveTime)
        return Routine(
            name: weekdays == [2, 3, 4, 5, 6] ? "Weekday mornings" : "Getting out the door",
            leaveHour: parts.hour ?? 8,
            leaveMinute: parts.minute ?? 15,
            weekdays: weekdays,
            steps: drafts.filter(\.isOn).map { RoutineStep(name: $0.name, guessMinutes: $0.minutes) }
        )
    }

    private var draftPlan: DeparturePlan {
        let calibration = Calibration(basePace: (pace ?? .quarterOver).multiplier, stepHistory: [], departures: [])
        let routine = draftRoutine
        let leave = routine.nextScheduledLeave(after: .now) ?? routine.leaveTimeForRunStarted(at: .now)
        return Planner.plan(routine, leaveAt: leave, calibration: calibration)
    }

    private func addCustom() {
        let name = customName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        let insertAt = max(drafts.count - 1, 0)
        drafts.insert(StepDraft(name: name, minutes: 10, isOn: true), at: insertAt)
        customName = ""
    }

    private func advance() {
        switch page {
        case 4:
            saveRoutine()
            isAdvancing = true
            Task {
                await NotificationService.shared.requestAuthorization()
                NotificationService.shared.reschedule(store: store)
                isAdvancing = false
                if purchases.isPro { finish() } else { page += 1 }
            }
        case Self.pageCount - 1:
            Task {
                if await purchases.purchase() == .purchased { finish() }
            }
        default:
            page += 1
        }
    }

    private func saveRoutine() {
        if let pace { store.setPace(pace) }
        guard store.routines.isEmpty else { return }
        store.save(draftRoutine)
    }

    private func finish() {
        saveRoutine()
        purchases.clearError()
        settings.hasCompletedSetup = true
    }
}

// MARK: - Pieces

struct StepDraft: Identifiable, Hashable {
    var id = UUID()
    var name: String
    var minutes: Int
    var isOn: Bool

    static var presets: [StepDraft] {
        [
            StepDraft(name: "Wake up and bathroom", minutes: 10, isOn: true),
            StepDraft(name: "Shower", minutes: 15, isOn: true),
            StepDraft(name: "Get dressed", minutes: 10, isOn: true),
            StepDraft(name: "Hair and makeup", minutes: 15, isOn: false),
            StepDraft(name: "Breakfast", minutes: 15, isOn: true),
            StepDraft(name: "Get the kids ready", minutes: 20, isOn: false),
            StepDraft(name: "Pack bag and lunch", minutes: 10, isOn: true),
            StepDraft(name: "Shoes, keys, out", minutes: 5, isOn: true),
        ]
    }
}

private struct StepDraftRow: View {
    @Binding var draft: StepDraft

    var body: some View {
        HStack(spacing: 12) {
            Button {
                draft.isOn.toggle()
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: draft.isOn ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(draft.isOn ? Theme.ink : Theme.secondary)
                    Text(draft.name)
                        .foregroundStyle(draft.isOn ? Theme.ink : Theme.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(draft.isOn ? .isSelected : [])
            MinuteStepper(minutes: $draft.minutes)
                .opacity(draft.isOn ? 1 : 0.35)
                .disabled(!draft.isOn)
        }
        .padding(.vertical, 10)
    }
}

/// "– 10 min +" in one compact control.
struct MinuteStepper: View {
    @Binding var minutes: Int

    private static let steps = [1, 2, 3, 5, 10, 15, 20, 25, 30, 40, 45, 60, 75, 90, 120]

    var body: some View {
        HStack(spacing: 0) {
            button("minus", enabled: minutes > Self.steps[0]) {
                minutes = Self.steps.last { $0 < minutes } ?? Self.steps[0]
            }
            Text("\(minutes) min")
                .font(.subheadline.monospacedDigit().weight(.semibold))
                .foregroundStyle(Theme.ink)
                .frame(minWidth: 56)
            button("plus", enabled: minutes < Self.steps.last!) {
                minutes = Self.steps.first { $0 > minutes } ?? minutes
            }
        }
        .background(Theme.background, in: Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(minutes) minutes")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: minutes = Self.steps.first { $0 > minutes } ?? minutes
            case .decrement: minutes = Self.steps.last { $0 < minutes } ?? minutes
            @unknown default: break
            }
        }
    }

    private func button(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.footnote.weight(.bold))
                .frame(width: 32, height: 32)
                .foregroundStyle(enabled ? Theme.ink : Theme.secondary.opacity(0.4))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}

private struct ChoiceRow: View {
    let title: String
    let detail: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(Theme.ink)
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondary)
                }
                Spacer()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? Theme.ink : Theme.hairline)
            }
            .padding(16)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(isSelected ? Theme.ink : Theme.hairline, lineWidth: isSelected ? 2 : 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Two bars: the guess, and the time it really takes.
struct GuessBars: View {
    let guess: Int
    let real: Int

    var body: some View {
        let longest = Double(max(guess, real, 1))
        VStack(alignment: .leading, spacing: 12) {
            bar(label: "Your guess", minutes: guess, fraction: Double(guess) / longest, color: Theme.hairline, text: Theme.secondary)
            bar(label: "Real time", minutes: real, fraction: Double(real) / longest, color: Theme.ink, text: Theme.ink)
        }
    }

    private func bar(label: String, minutes: Int, fraction: Double, color: Color, text: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label)
                Spacer()
                Text(Format.duration(minutes: minutes)).monospacedDigit()
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(text)
            GeometryReader { proxy in
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(color)
                    .frame(width: max(12, proxy.size.width * fraction))
            }
            .frame(height: 14)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct ProBenefit: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: symbol)
                .font(.title3.weight(.semibold))
                .foregroundStyle(Theme.ink)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(Theme.ink)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct PageDots: View {
    let count: Int
    let current: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<count, id: \.self) { index in
                Capsule()
                    .fill(index == current ? Theme.ink : Theme.hairline)
                    .frame(width: index == current ? 18 : 6, height: 6)
            }
        }
        .accessibilityHidden(true)
    }
}

/// The fleet onboarding bar: variable content grows upward, the primary
/// button and the reserved legal footer never move.
struct OnboardingBottomBar<Above: View>: View {
    let primaryTitle: String
    var isBusy = false
    var isDisabled = false
    let primaryAction: () -> Void
    let footer: OnboardingLegalFooter
    @ViewBuilder var above: () -> Above

    var body: some View {
        VStack(spacing: 0) {
            above()
            Button(action: primaryAction) {
                ZStack {
                    Text(primaryTitle).opacity(isBusy ? 0 : 1)
                    if isBusy { ProgressView().tint(Theme.inkInverse) }
                }
            }
            .buttonStyle(.primary)
            .disabled(isDisabled || isBusy)
            .padding(.top, 12)
            footer
                .padding(.top, 12)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 12)
    }
}

/// Restore, Terms and Privacy. Rendered on every onboarding page so the slot
/// keeps its height; hidden everywhere but the Pro page.
struct OnboardingLegalFooter: View {
    var isPlaceholder = false
    var isRestoring = false
    var onRestore: () -> Void = {}

    var body: some View {
        HStack(spacing: 14) {
            Button(isRestoring ? "Restoring…" : "Restore Purchase", action: onRestore)
                .disabled(isRestoring)
            Link("Terms of Use", destination: ShoesOnLinks.standardEULA)
            Link("Privacy Policy", destination: ShoesOnLinks.privacyPolicy)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(Theme.secondary)
        .frame(maxWidth: .infinity)
        .frame(height: 28)
        .opacity(isPlaceholder ? 0 : 1)
        .allowsHitTesting(!isPlaceholder)
        .accessibilityHidden(isPlaceholder)
    }
}
