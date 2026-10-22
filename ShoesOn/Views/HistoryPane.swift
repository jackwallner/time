import SwiftUI

/// The unfolded Duo's second screen beside Home and the run summary: the
/// on-time record and each recent morning, so the plan and how it has been
/// going sit side by side.
struct HistoryPane: View {
    @EnvironmentObject private var store: RoutineStore

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    if let routine = store.selectedRoutine {
                        let departures = store.departures(for: routine.id)
                        RecordCard(departures: departures, calibration: store.calibration)
                        if !departures.isEmpty {
                            RecentMorningsCard(departures: Array(departures.prefix(14)))
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 32)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("History")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

/// Each departure: the day, when they left against the target, and how far off.
private struct RecentMorningsCard: View {
    let departures: [DepartureRecord]

    var body: some View {
        Card {
            SectionLabel("Recent mornings")
                .padding(.bottom, 6)
            ForEach(departures) { record in
                row(record)
                if record.id != departures.last?.id {
                    Divider().overlay(Theme.hairline)
                }
            }
        }
    }

    private func row(_ record: DepartureRecord) -> some View {
        let color = Self.color(lateSeconds: record.lateSeconds)
        return HStack(spacing: 12) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 2) {
                Text(record.left.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                Text("Out \(Format.time(record.left)) for \(Format.time(record.target))")
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(Theme.secondary)
            }
            Spacer(minLength: 8)
            Text(Format.lateness(seconds: record.lateSeconds))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(color)
        }
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
    }

    /// The summary's scale: on time, a few minutes over, or properly late.
    private static func color(lateSeconds: TimeInterval) -> Color {
        if lateSeconds <= 60 { return Theme.onTrack }
        return lateSeconds < 5 * 60 ? Theme.behind : Theme.late
    }
}
