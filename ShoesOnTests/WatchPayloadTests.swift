import XCTest
@testable import ShoesOn

/// What the Watch and its complication read between messages from the phone.
final class WatchPayloadTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_790_000_000)

    private func departure(_ hours: Double) -> NextDepartureSnapshot {
        let leave = start.addingTimeInterval(hours * 3600)
        return NextDepartureSnapshot(routineName: "Mornings", alertAt: leave.addingTimeInterval(-3600), leaveAt: leave)
    }

    func testMovesOnOnceADeparturePasses() {
        let first = departure(1), second = departure(25)
        let payload = WatchPayload(isPro: true, run: nil, next: first, upcoming: [first, second], sentAt: start)
        XCTAssertEqual(payload.nextDeparture(now: start), first)
        XCTAssertEqual(payload.nextDeparture(now: start.addingTimeInterval(2 * 3600)), second)
        XCTAssertEqual(payload.widgetSnapshot.departures, [first, second])
    }

    /// A phone on an older build sends no `upcoming`; the single `next` still works.
    func testDecodesAPayloadWithoutUpcoming() throws {
        let old = WatchPayload(isPro: true, run: nil, next: departure(1), upcoming: nil, sentAt: start)
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(old)) as! [String: Any]
        json.removeValue(forKey: "upcoming")
        let decoded = try JSONDecoder().decode(WatchPayload.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(decoded.nextDeparture(now: start), departure(1))
        XCTAssertNil(decoded.nextDeparture(now: start.addingTimeInterval(2 * 3600)))
        XCTAssertEqual(decoded.widgetSnapshot.departures, [departure(1)])
    }
}
