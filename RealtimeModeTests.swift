import XCTest
@testable import BoxVerify_v1

@MainActor
final class RealtimeModeTests: XCTestCase {

    override func setUp() {
        super.setUp()
        BoxVerifyTestSupport.resetSessionManager()
    }

    func testRealtimeSessionStarts() {
        let sessionManager = SessionManager.shared

        XCTAssertNil(sessionManager.currentRealtimeSession)

        sessionManager.startRealtimeSessionIfNeeded(
            entitlementAtStart: BoxVerifyTestSupport.entitlement()
        )

        XCTAssertNotNil(sessionManager.currentRealtimeSession)
        XCTAssertEqual(sessionManager.currentRealtimeSession?.verificationScans, 0)
    }

    func testBaseCodeCanBeRegistered() {
        let sessionManager = SessionManager.shared

        sessionManager.startRealtimeSessionIfNeeded(
            entitlementAtStart: BoxVerifyTestSupport.entitlement()
        )

        let ok = sessionManager.setBaseCode("BASE-001")

        XCTAssertTrue(ok)
        XCTAssertEqual(sessionManager.baseCode, "BASE-001")
        XCTAssertEqual(sessionManager.currentRealtimeSession?.verificationScans, 0)
    }

    func testBaseCodeRejectsControlCharacters() {
        let sessionManager = SessionManager.shared

        sessionManager.startRealtimeSessionIfNeeded(
            entitlementAtStart: BoxVerifyTestSupport.entitlement()
        )

        let ok = sessionManager.setBaseCode("BASE-001\n")

        XCTAssertFalse(ok)
        XCTAssertNil(sessionManager.baseCode)
    }

    func testRealtimeVerificationScanCountIncrementsOnlyOnVerification() {
        let sessionManager = SessionManager.shared

        sessionManager.startRealtimeSessionIfNeeded(
            entitlementAtStart: BoxVerifyTestSupport.entitlement()
        )

        XCTAssertTrue(sessionManager.setBaseCode("BASE-001"))
        XCTAssertEqual(sessionManager.currentRealtimeSession?.verificationScans, 0)

        sessionManager.recordRealtimeVerification(code: "BASE-001", outcome: .ok)

        XCTAssertEqual(sessionManager.currentRealtimeSession?.verificationScans, 1)
        XCTAssertEqual(sessionManager.currentRealtimeSession?.lastScannedCode, "BASE-001")
        XCTAssertEqual(sessionManager.currentRealtimeSession?.lastOutcome, .ok)
    }

    func testRealtimeMismatchRecordsNG() {
        let sessionManager = SessionManager.shared

        sessionManager.startRealtimeSessionIfNeeded(
            entitlementAtStart: BoxVerifyTestSupport.entitlement()
        )

        XCTAssertTrue(sessionManager.setBaseCode("BASE-001"))

        sessionManager.recordRealtimeVerification(code: "BASE-999", outcome: .ng)

        XCTAssertEqual(sessionManager.currentRealtimeSession?.verificationScans, 1)
        XCTAssertEqual(sessionManager.currentRealtimeSession?.lastScannedCode, "BASE-999")
        XCTAssertEqual(sessionManager.currentRealtimeSession?.lastOutcome, .ng)
    }

    func testRealtimeFinishClearsSessionAndBaseCode() {
        let sessionManager = SessionManager.shared

        sessionManager.startRealtimeSessionIfNeeded(
            entitlementAtStart: BoxVerifyTestSupport.entitlement()
        )
        XCTAssertTrue(sessionManager.setBaseCode("BASE-001"))

        XCTAssertNotNil(sessionManager.currentRealtimeSession)
        XCTAssertEqual(sessionManager.baseCode, "BASE-001")

        sessionManager.finishCurrentSession(workType: .realtime)

        XCTAssertNil(sessionManager.currentRealtimeSession)
        XCTAssertNil(sessionManager.baseCode)
    }

    func testRealtimeSuspendStoresSuspendedSessionAndKeepsBaseCode() {
        let sessionManager = SessionManager.shared

        sessionManager.startRealtimeSessionIfNeeded(
            entitlementAtStart: BoxVerifyTestSupport.entitlement()
        )
        XCTAssertTrue(sessionManager.setBaseCode("BASE-001"))

        sessionManager.suspendCurrentSession(workType: .realtime)

        XCTAssertNil(sessionManager.currentRealtimeSession)
        XCTAssertNotNil(sessionManager.suspendedSession)
        XCTAssertEqual(sessionManager.baseCode, "BASE-001")

        if case .realtime(let suspended)? = sessionManager.suspendedSession?.payload {
            XCTAssertEqual(suspended.verificationScans, 0)
        } else {
            XCTFail("Realtime セッションが中断保存されていない")
        }
    }
}
