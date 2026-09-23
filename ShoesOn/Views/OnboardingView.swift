import SwiftUI

/// Six pages: what it does, the pace question, the leave time, the steps, the
/// reveal of the real plan, and the free-trial offer. The primary button sits
/// in exactly the same frame on every page (fleet onboarding contract).
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

    static let pageCount = 6

    init(startPage: Int = 0) {
        _page = State(initialValue: startPage)
        _leaveTime = State(initialValue: Calendar.current.date(bySettingHour: 8, minute: 15, second: 0, of: .now) ?? .now)
        if startPage >= 1 { _pace = State(initialValue: .halfOver) }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                content
                    .id(page)
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))
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
        .onChange(of: page) { _, newPage in
            if newPage == Self.pageCount - 1 {
                purchases.trackPaywallImpression(id: "shoeson_onboarding_trial")
            }
        }
    }

    // MARK: - Chrome

    private var header: some View {
        HStack {
            Button {
                withAnimation(.smooth) { page -= 1 }
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
            isBusy: isAdvancing || (isTrialPage && purchases.isPurchasing),
            isDisabled: !canContinue,
            primaryAction: advance,
            footer: OnboardingLegalFooter(isPlaceholder: !isTrialPage, isRestoring: purchases.isPurchasing) {
                Task {
                    await purchases.restore()
                    if purchases.isPro { finish() }
                }
            }
        ) {
            VStack(spacing: 6) {
                if isTrialPage {
                    if let message = purchases.errorMessage {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(Theme.late)
                            .multilineTextAlignment(.center)
                    }
                    Text(trialDisclosure)
                        .font(.footnote)
                        .foregroundStyle(Theme.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Get Started", action: finish)
                        .buttonStyle(.secondary)
                } else {
                    PageDots(count: Self.pageCount - 1, current: page)
                        .padding(.bottom, 6)
                }
            }
        }
        .background(Theme.background)
    }

    private var isTrialPage: Bool { page == Self.pageCount - 1 }

    private var trialEligible: Bool {
        guard let yearly = purchases.yearly else { return false }
        return purchases.isEligibleForTrial(yearly)
    }

    private var primaryTitle: String {
        guard isTrialPage else { return "Continue" }
        return trialEligible ? "Start 7-day free trial" : "Continue with Pro"
    }

    private var trialDisclosure: String {
        guard let yearly = purchases.yearly else { return "Loading plans…" }
        if trialEligible {
            return "Free for 7 days, then \(yearly.billedLabel). Cancel anytime in Settings at least 24 hours before the trial ends."
        }
        return "\(yearly.billedLabel). Renews automatically unless cancelled at least 24 hours before the period ends."
    }

    private var canContinue: Bool {
        switch page {
        case 1: pace != nil
        case 2: !weekdays.isEmpty
        case 3: drafts.contains { $0.isOn }
        case Self.pageCount - 1: purchases.yearly != nil
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
        default: trialPage
        }
    }

    private func title(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 34, weight: .heavy, design: .rounded))
            .foregroundStyle(Theme.ink)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func lead(_ text: String) -> some View {
        Text(text)
            .font(.body)
            .foregroundStyle(Theme.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 22) {
            Image("OnboardingMark")
                .resizable()
                .scaledToFit()
                .frame(width: 76, height: 76)
                .shadow(color: .black.opacity(0.18), radius: 16, y: 8)
                .padding(.top, 16)
                .accessibilityHidden(true)
            Text("Leave on time.\nFor real this time.")
                .font(.system(size: 40, weight: .heavy, design: .rounded))
                .foregroundStyle(Theme.ink)
            lead("Tell Shoes On when you walk out the door. It works backward through your routine, learns how long each step really takes you, and tells you when to start.")
            Card {
                SectionLabel("Why you run late")
                    .padding(.bottom, 14)
                GapBars(guess: 45, real: 68)
                Text("Most guesses run short. Shoes On plans with your real times.")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondary)
                    .padding(.top, 14)
            }
        }
    }

    private var pacePage: some View {
        VStack(alignment: .leading, spacing: 18) {
            title("When getting ready feels like an hour, it usually takes…")
            lead("Be honest. This only sets the starting point; your real times take over as you go.")
            VStack(spacing: 10) {
                ForEach(PaceAnswer.allCases) { answer in
                    PaceChoice(answer: answer, isSelected: pace == answer) {
                        withAnimation(.snappy) { pace = answer }
                    }
                }
            }
        }
    }

    private var leavePage: some View {
        VStack(alignment: .leading, spacing: 18) {
            title("When do you need to walk out the door?")
            DatePicker("Leave at", selection: $leaveTime, displayedComponents: .hourAndMinute)
                .datePickerStyle(.wheel)
                .labelsHidden()
                .frame(maxWidth: .infinity)
            VStack(alignment: .leading, spacing: 12) {
                SectionLabel("On these days")
                WeekdayPicker(selection: $weekdays)
            }
        }
    }

    private var stepsPage: some View {
        VStack(alignment: .leading, spacing: 18) {
            title("What happens before you leave?")
            lead("Guess how long each takes. Being wrong is fine; that's what Shoes On is for.")
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
            .overlay(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous).strokeBorder(Theme.hairline.opacity(0.7)))
        }
    }

    private var revealPage: some View {
        let plan = draftPlan
        return VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 2) {
                Text("It really takes")
                    .font(.system(.title2, design: .rounded).weight(.bold))
                    .foregroundStyle(Theme.secondary)
                Text(Format.duration(minutes: plan.realMinutes))
                    .font(.system(size: 60, weight: .heavy, design: .rounded))
                    .foregroundStyle(Theme.ink)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
            }
            GapBars(guess: plan.guessMinutes, real: plan.realMinutes)
            Card {
                SectionLabel("Your plan")
                    .padding(.bottom, 8)
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Start")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Theme.secondary)
                        Text(Format.time(plan.alertAt))
                            .font(.system(.title, design: .rounded).weight(.heavy))
                            .foregroundStyle(Theme.ink)
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
                    }
                }
            }
            lead("Shoes On nudges you at \(Format.time(plan.alertAt)), keeps you on pace step by step, and swaps these estimates for your real times as you use it.")
        }
    }

    private var trialPage: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 8) {
                title(trialEligible ? "Try Shoes On Pro free for 7 days" : "Shoes On Pro")
                lead("Your first routine stays free for good. Pro adds the rest of your week.")
            }
            VStack(alignment: .leading, spacing: 18) {
                ProBenefit(symbol: "rectangle.stack.fill", title: "Every routine", detail: "Workdays, school runs, the gym, weekends. Each learns its own times.")
                ProBenefit(symbol: "applewatch", title: "Apple Watch coach", detail: "Your step, the time left, and whether you're slipping. Tap Done from your wrist.")
            }
            if trialEligible, let yearly = purchases.yearly {
                TrialTimeline(billed: yearly.billedLabel)
            }
        }
    }

    // MARK: - Actions

    private var draftRoutine: Routine {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: leaveTime)
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
        withAnimation(.snappy) {
            drafts.insert(StepDraft(name: name, minutes: 10, isOn: true), at: insertAt)
        }
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
                if purchases.isPro { finish() } else { withAnimation(.smooth) { page += 1 } }
            }
        case Self.pageCount - 1:
            guard let yearly = purchases.yearly else { return }
            Task {
                if await purchases.purchase(yearly) == .purchased { finish() }
            }
        default:
            withAnimation(.smooth) { page += 1 }
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
        withAnimation(.smooth) { settings.hasCompletedSetup = true }
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
                withAnimation(.snappy) { draft.isOn.toggle() }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: draft.isOn ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(draft.isOn ? Theme.ink : Theme.secondary)
                        .contentTransition(.symbolEffect(.replace))
                    Text(draft.name)
                        .foregroundStyle(draft.isOn ? Theme.ink : Theme.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .sensoryFeedback(.selection, trigger: draft.isOn)
            .accessibilityAddTraits(draft.isOn ? .isSelected : [])
            MinuteStepper(minutes: $draft.minutes)
                .opacity(draft.isOn ? 1 : 0.35)
                .disabled(!draft.isOn)
        }
        .padding(.vertical, 10)
    }
}

/// One pace answer, with a bar showing how far an hour stretches.
private struct PaceChoice: View {
    let answer: PaceAnswer
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(answer.title)
                            .font(.headline)
                            .foregroundStyle(Theme.ink)
                        Text(answer.detail)
                            .font(.subheadline)
                            .foregroundStyle(Theme.secondary)
                    }
                    Spacer()
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(isSelected ? Theme.ink : Theme.hairline)
                        .contentTransition(.symbolEffect(.replace))
                }
                GeometryReader { proxy in
                    let unit = proxy.size.width / 2
                    HStack(spacing: 0) {
                        Capsule().fill(Theme.ink.opacity(isSelected ? 1 : 0.25)).frame(width: unit)
                        if answer.multiplier > 1 {
                            Capsule().fill(Theme.gap.opacity(isSelected ? 1 : 0.35))
                                .frame(width: unit * (answer.multiplier - 1))
                                .padding(.leading, 3)
                        }
                    }
                }
                .frame(height: 6)
            }
            .padding(16)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(isSelected ? Theme.ink : Theme.hairline.opacity(0.7), lineWidth: isSelected ? 2 : 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: isSelected)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

struct ProBenefit: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Theme.inkInverse)
                .frame(width: 38, height: 38)
                .background(Theme.ink, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(Theme.ink)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Today, the reminder, the first charge. Only shown when a trial applies, and
/// the reminder is real: `NotificationService.scheduleTrialReminder`.
struct TrialTimeline: View {
    let billed: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            row(symbol: "lock.open.fill", title: "Today", detail: "Every routine and the Watch coach, free.", isLast: false)
            row(symbol: "bell.fill", title: "Day 5", detail: "A reminder before your trial ends.", isLast: false)
            row(symbol: "calendar", title: "Day 7", detail: "\(billed) begins, unless you cancel.", isLast: true)
        }
    }

    private func row(symbol: String, title: String, detail: String, isLast: Bool) -> some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(spacing: 0) {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.ink)
                    .frame(width: 30, height: 30)
                    .background(Theme.raised, in: Circle())
                if !isLast {
                    Rectangle().fill(Theme.hairline).frame(width: 2).frame(maxHeight: .infinity)
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.bold)).foregroundStyle(Theme.ink)
                Text(detail).font(.subheadline).foregroundStyle(Theme.secondary)
            }
            .padding(.bottom, isLast ? 0 : 14)
            .padding(.top, 5)
        }
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
                    .frame(width: index == current ? 20 : 6, height: 6)
            }
        }
        .animation(.snappy, value: current)
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
            .padding(.top, 10)
            footer
                .padding(.top, 10)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 10)
    }
}

/// Restore, Terms and Privacy. Rendered on every onboarding page so the slot
/// keeps its height; hidden everywhere but the trial page.
struct OnboardingLegalFooter: View {
    var isPlaceholder = false
    var isRestoring = false
    var onRestore: () -> Void = {}

    var body: some View {
        HStack(spacing: 14) {
            Button(isRestoring ? "Restoring…" : "Restore", action: onRestore)
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
