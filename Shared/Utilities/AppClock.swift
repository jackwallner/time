import Foundation

/// The app's notion of now. Always the real clock in Release; in DEBUG,
/// `-FixedNow HH:mm` shifts it so App Store captures show a believable
/// morning instead of whatever time the capture happened to run.
enum AppClock {
    #if DEBUG
    static let offset: TimeInterval = {
        guard let value = ScreenshotConfig.value(after: "-FixedNow") else { return 0 }
        let parts = value.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2,
              let target = Calendar.current.date(bySettingHour: parts[0], minute: parts[1], second: 0, of: .now)
        else { return 0 }
        return target.timeIntervalSince(.now)
    }()
    #else
    static let offset: TimeInterval = 0
    #endif

    static var now: Date { Date().addingTimeInterval(offset) }

    static func adjust(_ date: Date) -> Date { date.addingTimeInterval(offset) }
}
