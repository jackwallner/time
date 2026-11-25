import RevenueCat
import XCTest
@testable import ShoesOn

/// Ask to Buy reads as waiting, a lost connection as the connection line,
/// and every other failure as before.
final class PurchaseFailureTests: XCTestCase {
    func testAskToBuyIsWaitingForApprovalNotAnError() {
        let failure = PurchaseFailure(ErrorCode.paymentPendingError)
        XCTAssertEqual(failure, .pending)
        XCTAssertEqual(failure.message(startedTrial: true), "Waiting for approval. Your purchase unlocks once it is approved.")
        XCTAssertEqual(failure.message(startedTrial: false), PurchaseFailure.pendingMessage)
    }

    /// RevenueCat's errors also arrive bridged to NSError.
    func testABridgedPendingErrorIsStillPending() {
        let domain = (ErrorCode.paymentPendingError as NSError).domain
        let bridged = NSError(domain: domain, code: ErrorCode.paymentPendingError.rawValue)
        XCTAssertEqual(PurchaseFailure(bridged), .pending)
        // The same number from another framework is not Ask to Buy.
        XCTAssertEqual(PurchaseFailure(NSError(domain: NSCocoaErrorDomain, code: ErrorCode.paymentPendingError.rawValue)), .failed)
    }

    func testNetworkErrorsReadAsTheConnectionLine() {
        XCTAssertEqual(PurchaseFailure(ErrorCode.networkError), .offline)
        XCTAssertEqual(PurchaseFailure(ErrorCode.offlineConnectionError), .offline)
        XCTAssertEqual(
            PurchaseFailure.offline.message(startedTrial: true),
            "Purchases aren't available right now. Check your connection and try again."
        )
    }

    func testOtherErrorsKeepTheirCopy() {
        XCTAssertEqual(PurchaseFailure(ErrorCode.purchaseCancelledError), .cancelled)
        XCTAssertNil(PurchaseFailure.cancelled.message(startedTrial: true))
        XCTAssertEqual(PurchaseFailure(ErrorCode.purchaseNotAllowedError), .failed)
        XCTAssertEqual(PurchaseFailure(ErrorCode.storeProblemError), .failed)
        XCTAssertEqual(PurchaseFailure(NSError(domain: NSURLErrorDomain, code: -1)), .failed)
        XCTAssertEqual(PurchaseFailure.failed.message(startedTrial: true), "Couldn't start your trial. Please try again.")
        XCTAssertEqual(PurchaseFailure.failed.message(startedTrial: false), "Couldn't complete the purchase. Please try again.")
    }

    func testPurchaseCopyHasNoDashes() {
        let lines = [PurchaseFailure.pendingMessage, PurchaseFailure.offlineMessage]
        for line in lines {
            XCTAssertFalse(line.contains("\u{2014}") || line.contains("\u{2013}"), line)
        }
    }
}
