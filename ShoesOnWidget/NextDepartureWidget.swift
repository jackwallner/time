import SwiftUI
import WidgetKit

/// The next start time where it is seen without opening anything: the Lock
/// Screen, StandBy and the Home Screen. Within the hour it becomes a live
/// countdown, because "7:32" means little to someone who cannot feel time
/// passing and "11:48" going down means a lot.
struct NextDepartureWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetSnapshot.kind, provider: DepartureProvider()) { entry in
            DepartureWidgetView(entry: entry)
                .containerBackground(for: .widget) { Theme.background }
        }
        .configurationDisplayName("Next start")
        .description("When to start getting ready, counting down in the last hour.")
        .supportedFamilies([.systemSmall, .accessoryRectangular, .accessoryCircular, .accessoryInline])
    }
}

struct DepartureEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?

    /// The run in progress, until well after its leave time.
    var run: RunSnapshot? {
        guard let run = snapshot?.run, date < run.leaveAt.addingTimeInterval(30 * 60) else { return nil }
        return run
    }

    /// The first departure not yet due at this entry's moment.
    var next: NextDepartureSnapshot? {
        snapshot?.departures.first { $0.leaveAt > date }
    }
}

struct DepartureProvider: TimelineProvider {
    /// The countdown shows from this long before the start.
    static let countdownWindow: TimeInterval = 3600

    func placeholder(in context: Context) -> DepartureEntry {
        DepartureEntry(date: .now, snapshot: Self.sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (DepartureEntry) -> Void) {
        completion(DepartureEntry(date: .now, snapshot: context.isPreview ? Self.sample : Self.load() ?? Self.sample))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<DepartureEntry>) -> Void) {
        let now = Date.now
        let snapshot = Self.load()
        var moments: Set<Date> = [now]
        for departure in snapshot?.departures ?? [] {
            moments.insert(departure.alertAt.addingTimeInterval(-Self.countdownWindow))
            moments.insert(departure.alertAt)
            moments.insert(departure.leaveAt)
        }
        if let run = snapshot?.run { moments.insert(run.leaveAt.addingTimeInterval(30 * 60)) }
        let entries = moments
            .filter { $0 >= now }
            .sorted()
            .prefix(40)
            .map { DepartureEntry(date: $0, snapshot: snapshot) }
        completion(Timeline(entries: Array(entries), policy: .atEnd))
    }

    static func load() -> WidgetSnapshot? {
        guard let data = UserDefaults(suiteName: AppGroup.identifier)?.data(forKey: WidgetSnapshot.defaultsKey) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    static var sample: WidgetSnapshot {
        let alert = Date.now.addingTimeInterval(14 * 60)
        return WidgetSnapshot(
            departures: [NextDepartureSnapshot(routineName: "Weekday mornings", alertAt: alert, leaveAt: alert.addingTimeInterval(68 * 60))],
            run: nil
        )
    }
}

/// What a moment looks like, shared by every family.
private enum Phase {
    case running(RunSnapshot)
    case later(NextDepartureSnapshot)
    case countdown(NextDepartureSnapshot)
    case overdue(NextDepartureSnapshot)
    case none

    init(_ entry: DepartureEntry) {
        if let run = entry.run {
            self = .running(run)
        } else if let next = entry.next {
            if next.alertAt <= entry.date {
                self = .overdue(next)
            } else if next.alertAt.timeIntervalSince(entry.date) <= DepartureProvider.countdownWindow {
                self = .countdown(next)
            } else {
                self = .later(next)
            }
        } else {
            self = .none
        }
    }
}

struct DepartureWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: DepartureEntry

    var body: some View {
        let phase = Phase(entry)
        switch family {
        case .accessoryInline: inline(phase)
        case .accessoryCircular: circular(phase)
        case .accessoryRectangular: rectangular(phase)
        default: small(phase)
        }
    }

    // MARK: - Lock Screen

    @ViewBuilder private func inline(_ phase: Phase) -> some View {
        switch phase {
        case .running(let run): Text("Getting ready · out \(Format.time(run.leaveAt))")
        case .later(let next): Text("Start \(Format.time(next.alertAt)) · out \(Format.time(next.leaveAt))")
        case .countdown(let next): Text("Start in \(Text(timerInterval: entry.date...next.alertAt, countsDown: true))")
        case .overdue(let next): Text("Start now · out \(Format.time(next.leaveAt))")
        case .none: Text("No departure set")
        }
    }

    @ViewBuilder private func circular(_ phase: Phase) -> some View {
        switch phase {
        case .countdown(let next):
            ProgressView(timerInterval: next.alertAt.addingTimeInterval(-DepartureProvider.countdownWindow)...next.alertAt, countsDown: true) {
                Image(systemName: "figure.walk")
            } currentValueLabel: {
                Text(timerInterval: entry.date...next.alertAt, countsDown: true, showsHours: false)
                    .font(.system(.caption, design: .rounded).weight(.bold))
                    .minimumScaleFactor(0.6)
            }
            .progressViewStyle(.circular)
        default:
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 1) {
                    Image(systemName: phase.isUrgent ? "figure.walk.departure" : "figure.walk")
                        .font(.caption.weight(.semibold))
                    Text(phase.circularText)
                        .font(.system(.caption2, design: .rounded).weight(.bold))
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                }
                .padding(4)
            }
        }
    }

    private func rectangular(_ phase: Phase) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(phase.routineName ?? "Shoes On")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            headline(phase)
                .font(.system(.headline, design: .rounded).weight(.heavy))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(phase.footer(now: entry.date))
                .font(.caption)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .widgetAccentable()
    }

    // MARK: - Home Screen

    private func small(_ phase: Phase) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(phase.routineName ?? "Shoes On")
                .font(.caption.weight(.bold))
                .foregroundStyle(Theme.secondary)
                .textCase(.uppercase)
                .lineLimit(1)
            Spacer(minLength: 4)
            Text(phase.smallLabel)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.secondary)
            headline(phase)
                .font(.system(size: 34, weight: .heavy, design: .rounded).monospacedDigit())
                .foregroundStyle(phase.isUrgent ? Theme.late : Theme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Spacer(minLength: 4)
            HStack(spacing: 6) {
                Circle().fill(Theme.onTrack).frame(width: 7, height: 7)
                Text(phase.footer(now: entry.date))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    @ViewBuilder private func headline(_ phase: Phase) -> some View {
        switch phase {
        case .running(let run): Text(run.isLeaving ? "Head out" : (run.stepName ?? "Getting ready"))
        case .later(let next): Text(family == .systemSmall ? Format.time(next.alertAt) : "Start \(Format.time(next.alertAt))")
        case .countdown(let next):
            if family == .systemSmall {
                Text(timerInterval: entry.date...next.alertAt, countsDown: true)
            } else {
                Text("Start in \(Text(timerInterval: entry.date...next.alertAt, countsDown: true))")
            }
        case .overdue: Text("Start now")
        case .none: Text(family == .systemSmall ? "None" : "No departure")
        }
    }
}

private extension Phase {
    var routineName: String? {
        switch self {
        case .running(let run): run.routineName
        case .later(let next), .countdown(let next), .overdue(let next): next.routineName
        case .none: nil
        }
    }

    var isUrgent: Bool {
        if case .overdue = self { return true }
        return false
    }

    var smallLabel: String {
        switch self {
        case .running: "Now"
        case .later: "Start at"
        case .countdown: "Start in"
        case .overdue: "Late to start"
        case .none: "Next start"
        }
    }

    var circularText: String {
        switch self {
        case .running: "Go"
        case .later(let next): Format.time(next.alertAt)
        case .countdown: ""
        case .overdue: "Now"
        case .none: "Off"
        }
    }

    func footer(now: Date) -> String {
        switch self {
        case .running(let run): "Out the door \(Format.time(run.leaveAt))"
        case .later(let next), .countdown(let next), .overdue(let next):
            Calendar.current.isDate(next.leaveAt, inSameDayAs: now)
                ? "Out the door \(Format.time(next.leaveAt))"
                : "\(Format.day(next.leaveAt, now: now)), out \(Format.time(next.leaveAt))"
        case .none: "Set one in the app"
        }
    }
}
