import XCTest
@testable import BoxVerify_v1

@MainActor
final class KitCheckModeTests: XCTestCase {

    override func setUp() {
        super.setUp()
        BoxVerifyTestSupport.resetSessionManager()
    }

    // ============================================================
    // MARK: - Start
    // ============================================================

    func testKitSessionStarts() {
        let sessionManager = SessionManager.shared

        XCTAssertNil(sessionManager.currentKitSession)

        sessionManager.startKitSessionIfNeeded(
            entitlementAtStart: BoxVerifyTestSupport.entitlement()
        )

        XCTAssertNotNil(sessionManager.currentKitSession)
        XCTAssertNil(sessionManager.currentKitSession?.kitId)
    }

    // ============================================================
    // MARK: - KitID selection
    // ============================================================

    func testKitIdSelectionLoadsDefinition() {
        let sessionManager = SessionManager.shared
        let kit = BoxVerifyTestSupport.makeKitDefinition()

        sessionManager.upsertKit(
            kitId: kit.kitId,
            requiredCounts: kit.requiredCounts
        )

        sessionManager.startKitSessionIfNeeded(
            entitlementAtStart: BoxVerifyTestSupport.entitlement()
        )

        sessionManager.selectKitId(kit.kitId)

        XCTAssertEqual(sessionManager.currentKitSession?.kitId, kit.kitId)
        XCTAssertEqual(sessionManager.currentKitSession?.requiredCounts["ITEM-A"], 2)
        XCTAssertEqual(sessionManager.currentKitSession?.requiredCounts["ITEM-B"], 1)
        XCTAssertEqual(sessionManager.currentKitSession?.scannedCounts.count, 0)
    }

    // ============================================================
    // MARK: - Progress -> Complete
    // ============================================================

    func testKitProgressThenCompletedOK() {
        let sessionManager = SessionManager.shared
        let kit = BoxVerifyTestSupport.makeKitDefinition()

        sessionManager.upsertKit(
            kitId: kit.kitId,
            requiredCounts: kit.requiredCounts
        )

        sessionManager.startKitSessionIfNeeded(
            entitlementAtStart: BoxVerifyTestSupport.entitlement()
        )

        sessionManager.selectKitId(kit.kitId)

        let result1 = sessionManager.scanKitComponent("ITEM-A")
        let result2 = sessionManager.scanKitComponent("ITEM-A")
        let result3 = sessionManager.scanKitComponent("ITEM-B")

        assertKitOutcome(result1, is: .progress)
        assertKitOutcome(result2, is: .progress)
        assertKitOutcome(result3, is: .completedOK)

        XCTAssertEqual(sessionManager.currentKitSession?.scannedCounts["ITEM-A"], 2)
        XCTAssertEqual(sessionManager.currentKitSession?.scannedCounts["ITEM-B"], 1)
    }

    // ============================================================
    // MARK: - Unknown Code
    // ============================================================

    func testKitUnknownCodeReturnsNG() {
        let sessionManager = SessionManager.shared
        let kit = BoxVerifyTestSupport.makeKitDefinition()

        sessionManager.upsertKit(
            kitId: kit.kitId,
            requiredCounts: kit.requiredCounts
        )

        sessionManager.startKitSessionIfNeeded(
            entitlementAtStart: BoxVerifyTestSupport.entitlement()
        )

        sessionManager.selectKitId(kit.kitId)

        let result = sessionManager.scanKitComponent("UNKNOWN")

        if case .completedNG(let reason) = result {
            XCTAssertFalse(reason.isEmpty)
        } else {
            XCTFail("未知コードは completedNG を返す想定")
        }
    }

    // ============================================================
    // MARK: - Over Required
    // ============================================================

    func testKitOverRequiredReturnsNG() {
        let sessionManager = SessionManager.shared
        let kit = BoxVerifyTestSupport.makeKitDefinition()

        sessionManager.upsertKit(
            kitId: kit.kitId,
            requiredCounts: kit.requiredCounts
        )

        sessionManager.startKitSessionIfNeeded(
            entitlementAtStart: BoxVerifyTestSupport.entitlement()
        )

        sessionManager.selectKitId(kit.kitId)

        // ITEM-B は required=1 だが、ITEM-A が未完了なので 1回目は progress
        assertKitOutcome(sessionManager.scanKitComponent("ITEM-B"), is: .progress)

        let result = sessionManager.scanKitComponent("ITEM-B")

        if case .completedNG(let reason) = result {
            XCTAssertFalse(reason.isEmpty)
        } else {
            XCTFail("必要数超過は completedNG を返す想定")
        }
    }

    // ============================================================
    // MARK: - No Session
    // ============================================================

    func testKitNoSessionReturnsNoSession() {
        let sessionManager = SessionManager.shared

        let result = sessionManager.scanKitComponent("ITEM-A")

        assertKitOutcome(result, is: .noSession)
    }

    // ============================================================
    // MARK: - Suspend
    // ============================================================

    func testKitSuspendStoresSuspendedSession() {
        let sessionManager = SessionManager.shared
        let kit = BoxVerifyTestSupport.makeKitDefinition()

        sessionManager.upsertKit(
            kitId: kit.kitId,
            requiredCounts: kit.requiredCounts
        )

        sessionManager.startKitSessionIfNeeded(
            entitlementAtStart: BoxVerifyTestSupport.entitlement()
        )

        sessionManager.selectKitId(kit.kitId)

        _ = sessionManager.scanKitComponent("ITEM-A")

        sessionManager.suspendCurrentSession(workType: .kit)

        XCTAssertNil(sessionManager.currentKitSession)
        XCTAssertNotNil(sessionManager.suspendedSession)

        if case .kit(let suspended)? = sessionManager.suspendedSession?.payload {
            XCTAssertEqual(suspended.kitId, kit.kitId)
            XCTAssertEqual(suspended.scannedCounts["ITEM-A"], 1)
            XCTAssertEqual(suspended.requiredCounts["ITEM-A"], 2)
            XCTAssertEqual(suspended.requiredCounts["ITEM-B"], 1)
        } else {
            XCTFail("Kitセッションが中断保存されていない")
        }
    }

    // ============================================================
    // MARK: - Helpers
    // ============================================================

    private enum ExpectedKitOutcome {
        case progress
        case completedOK
        case noSession
    }

    private func assertKitOutcome(
        _ actual: KitScanOutcome,
        is expected: ExpectedKitOutcome,
        _ message: String = "",
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        switch (actual, expected) {
        case (.progress, .progress),
             (.completedOK, .completedOK),
             (.noSession, .noSession):
            return

        default:
            XCTFail(
                message.isEmpty ? "Unexpected KitScanOutcome" : message,
                file: file,
                line: line
            )
        }
    }
}
