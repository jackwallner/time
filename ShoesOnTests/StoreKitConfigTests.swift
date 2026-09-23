import StoreKit
import XCTest
@testable import ShoesOn

/// The local StoreKit catalog must carry both plans with their free weeks, or
/// the paywall renders and screenshots are wrong.
final class StoreKitConfigTests: XCTestCase {
    func testCatalogHasBothPlansWithFreeWeek() async throws {
        let products = try await Product.products(for: ShoesOnProduct.all)
        let byID = Dictionary(uniqueKeysWithValues: products.map { ($0.id, $0) })
        XCTAssertEqual(Set(byID.keys), ShoesOnProduct.all)
        for id in ShoesOnProduct.all {
            let intro = byID[id]?.subscription?.introductoryOffer
            XCTAssertEqual(intro?.paymentMode, .freeTrial, id)
            let days = intro.map { $0.period.unit == .week ? $0.period.value * 7 : $0.period.value }
            XCTAssertEqual(days, 7, id)
        }
        XCTAssertEqual(byID[ShoesOnProduct.yearly]?.displayPrice, "$9.99")
        XCTAssertEqual(byID[ShoesOnProduct.monthly]?.displayPrice, "$1.99")
    }
}
