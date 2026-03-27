import XCTest
@testable import BoxVerify_v1

@MainActor
final class ScanStatsModeTests: XCTestCase {

    override func setUp() {
        super.setUp()
        BoxVerifyTestSupport.resetSessionManager()
    }

    func testScanStatsSessionStarts() {
        let sessionManager = SessionManager.shared

        XCTAssertNil(sessionManager.currentScanStatsSession)

        sessionManager.startScanStatsSessionIfNeeded(
            entitlementAtStart: BoxVerifyTestSupport.entitlement()
        )

        XCTAssertNotNil(sessionManager.currentScanStatsSession)
        XCTAssertEqual(sessionManager.currentScanStatsSession?.totalScans, 0)
        XCTAssertEqual(sessionManager.currentScanStatsSession?.codeCounts.count, 0)
    }

    func testScanStatsCountsSingleCode() {
        let sessionManager = SessionManager.shared

        sessionManager.startScanStatsSessionIfNeeded(
            entitlementAtStart: BoxVerifyTestSupport.entitlement()
        )

        let result1 = sessionManager.scanStatsCount("CODE-A")
        let result2 = sessionManager.scanStatsCount("CODE-A")

        assertScanStatsResult(result1, is: .success)
        assertScanStatsResult(result2, is: .success)

        XCTAssertEqual(sessionManager.currentScanStatsSession?.totalScans, 2)
        XCTAssertEqual(sessionManager.currentScanStatsSession?.codeCounts["CODE-A"], 2)
    }

    func testScanStatsCountsDifferentCodes() {
        let sessionManager = SessionManager.shared

        sessionManager.startScanStatsSessionIfNeeded(
            entitlementAtStart: BoxVerifyTestSupport.entitlement()
        )

        let r1 = sessionManager.scanStatsCount("CODE-01")
        let r2 = sessionManager.scanStatsCount("CODE-02")
        let r3 = sessionManager.scanStatsCount("CODE-03")

        assertScanStatsResult(r1, is: .success)
        assertScanStatsResult(r2, is: .success)
        assertScanStatsResult(r3, is: .success)

        XCTAssertEqual(sessionManager.currentScanStatsSession?.totalScans, 3)
        XCTAssertEqual(sessionManager.currentScanStatsSession?.codeCounts.count, 3)
    }

    func testScanStatsStopsAt10Types() {
        let sessionManager = SessionManager.shared

        sessionManager.startScanStatsSessionIfNeeded(
            entitlementAtStart: BoxVerifyTestSupport.entitlement()
        )

        for i in 1...10 {
            let result = sessionManager.scanStatsCount("TYPE-\(i)")
            assertScanStatsResult(result, is: .success, "10種類目までは success の想定")
        }

        let result11 = sessionManager.scanStatsCount("TYPE-11")

        assertScanStatsResult(result11, is: .maxTypesReached)
        XCTAssertEqual(sessionManager.currentScanStatsSession?.codeCounts.count, 10)
        XCTAssertNil(sessionManager.currentScanStatsSession?.codeCounts["TYPE-11"])
    }

    func testScanStatsStopsAt1000Total() {
        let sessionManager = SessionManager.shared

        sessionManager.startScanStatsSessionIfNeeded(
            entitlementAtStart: BoxVerifyTestSupport.entitlement()
        )

        for _ in 1...1000 {
            let result = sessionManager.scanStatsCount("CODE-A")
            assertScanStatsResult(result, is: .success, "1000回目までは success の想定")
        }

        let result1001 = sessionManager.scanStatsCount("CODE-A")

        assertScanStatsResult(result1001, is: .maxTotalReached)
        XCTAssertEqual(sessionManager.currentScanStatsSession?.totalScans, 1000)
        XCTAssertEqual(sessionManager.currentScanStatsSession?.codeCounts["CODE-A"], 1000)
    }

    func testScanStatsReturnsNoSessionWhenNotStarted() {
        let sessionManager = SessionManager.shared

        XCTAssertNil(sessionManager.currentScanStatsSession)

        let result = sessionManager.scanStatsCount("CODE-A")

        assertScanStatsResult(result, is: .noSession)
    }

    func testScanStatsSuspendStoresSuspendedSession() {
        let sessionManager = SessionManager.shared

        sessionManager.startScanStatsSessionIfNeeded(
            entitlementAtStart: BoxVerifyTestSupport.entitlement()
        )
        _ = sessionManager.scanStatsCount("CODE-A")

        sessionManager.suspendCurrentSession(workType: .scanStats)

        XCTAssertNil(sessionManager.currentScanStatsSession)
        XCTAssertNotNil(sessionManager.suspendedSession)

        if case .scanStats(let suspended)? = sessionManager.suspendedSession?.payload {
            XCTAssertEqual(suspended.totalScans, 1)
            XCTAssertEqual(suspended.codeCounts["CODE-A"], 1)
        } else {
            XCTFail("Scan Stats セッションが中断保存されていない")
        }
    }

    // MARK: - Helpers

    private enum ExpectedScanStatsResult {
        case success
        case maxTypesReached
        case maxTotalReached
        case noSession
    }

    private func assertScanStatsResult(
        _ actual: ScanStatsCountResult,
        is expected: ExpectedScanStatsResult,
        _ message: String = "",
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        switch (actual, expected) {
        case (.success, .success),
             (.maxTypesReached, .maxTypesReached),
             (.maxTotalReached, .maxTotalReached),
             (.noSession, .noSession):
            return

        default:
            XCTFail(
                message.isEmpty ? "Unexpected ScanStatsCountResult" : message,
                file: file,
                line: line
            )
        }
    }
}
