import XCTest
@testable import BoxVerify_v1

@MainActor
final class FreeTrialExperienceTests: XCTestCase {

    override func setUp() {
        super.setUp()
        FreeTrialTestSupport.resetSessionManager()
        FreeTrialTestSupport.resetScanStatsTrialLimiter()
        FreeTrialTestSupport.resetKitTrialLimiter()
    }

    // MARK: - Realtime 無料体験（1日1回）
    //
    // ⚠️ このテストは実行すると、その日の無料枠を消費する可能性がある。
    // 環境変数 RUN_DESTRUCTIVE_REALTIME_TRIAL_TESTS=1 の時だけ実行する。
    //

    func testRealtimeTrial_AllowsOneAttemptThenExhausts() throws {
        guard FreeTrialTestSupport.shouldRunDestructiveRealtimeTrialTest() else {
            throw XCTSkip("RUN_DESTRUCTIVE_REALTIME_TRIAL_TESTS=1 の時だけ実行する destructive test です。")
        }

        RealtimeTrialLimiter.resetIfNewDay()

        let before = RealtimeTrialLimiter.status()

        if before.isExhausted {
            throw XCTSkip("この端末では本日のRealtime無料枠がすでに消費済みです。日付切替後に実行してください。")
        }

        let recorded = RealtimeTrialLimiter.recordAttempt()
        XCTAssertTrue(recorded, "未消費状態なら1回目は記録成功する想定")

        let after = RealtimeTrialLimiter.status()
        XCTAssertTrue(after.isExhausted, "1回消費後は当日上限到達の想定")
    }

    // MARK: - Scan Stats 未購入体験（最初の5回）

    func testScanStatsTrialLimiter_AllowsFirstFivePreviews() {
        XCTAssertEqual(ScanStatsTrialLimiter.previewCount(), 0)
        XCTAssertEqual(ScanStatsTrialLimiter.remainingPreviewCount(), 5)
        XCTAssertTrue(ScanStatsTrialLimiter.canShowPreview())
        XCTAssertFalse(ScanStatsTrialLimiter.hasReachedLimit())

        for expected in 1...5 {
            XCTAssertTrue(
                ScanStatsTrialLimiter.canShowPreview(),
                "\(expected)回目の直前までは体験可能の想定"
            )

            let newValue = ScanStatsTrialLimiter.recordPreviewUse()
            XCTAssertEqual(newValue, expected)
            XCTAssertEqual(ScanStatsTrialLimiter.previewCount(), expected)
            XCTAssertEqual(ScanStatsTrialLimiter.remainingPreviewCount(), max(0, 5 - expected))
        }

        XCTAssertFalse(
            ScanStatsTrialLimiter.canShowPreview(),
            "5回使い切った後は体験不可の想定"
        )
        XCTAssertEqual(ScanStatsTrialLimiter.previewCount(), 5)
        XCTAssertEqual(ScanStatsTrialLimiter.remainingPreviewCount(), 0)
        XCTAssertTrue(ScanStatsTrialLimiter.hasReachedLimit())
    }

    func testScanStatsSession_TrialFlow_ShowsPreviewForFiveThenLocks() {
        let sessionManager = SessionManager.shared

        sessionManager.startScanStatsSessionIfNeeded(
            entitlementAtStart: FreeTrialTestSupport.entitlement()
        )

        XCTAssertNotNil(sessionManager.currentScanStatsSession)
        XCTAssertEqual(sessionManager.currentScanStatsSession?.totalScans, 0)
        XCTAssertEqual(ScanStatsTrialLimiter.previewCount(), 0)

        // 1〜5回目：内部計上 + preview可能
        for i in 1...5 {
            let result = sessionManager.scanStatsCount("CODE-\(i)")
            assertScanStatsResult(result, is: .success, "\(i)回目は内部計上 success の想定")

            XCTAssertEqual(sessionManager.currentScanStatsSession?.totalScans, i)
            XCTAssertEqual(sessionManager.currentScanStatsSession?.codeCounts.count, i)

            XCTAssertTrue(
                ScanStatsTrialLimiter.canShowPreview(),
                "\(i)回目の計上直後、UI側で recordPreviewUse 前ならまだ canShowPreview=true の想定"
            )

            let recorded = ScanStatsTrialLimiter.recordPreviewUse()
            XCTAssertEqual(recorded, i)
        }

        // 5回使い切った後は preview lock
        XCTAssertFalse(ScanStatsTrialLimiter.canShowPreview())
        XCTAssertEqual(ScanStatsTrialLimiter.previewCount(), 5)
        XCTAssertEqual(ScanStatsTrialLimiter.remainingPreviewCount(), 0)
        XCTAssertTrue(ScanStatsTrialLimiter.hasReachedLimit())

        // 6回目：内部計上は進むが preview は不可
        let result6 = sessionManager.scanStatsCount("CODE-6")
        assertScanStatsResult(result6, is: .success, "6回目も内部計上自体は success の想定")

        XCTAssertEqual(sessionManager.currentScanStatsSession?.totalScans, 6)
        XCTAssertEqual(sessionManager.currentScanStatsSession?.codeCounts.count, 6)
        XCTAssertFalse(
            ScanStatsTrialLimiter.canShowPreview(),
            "6回目以降は体験表示不可の想定"
        )
    }

    func testScanStatsTrial_StillRespectsPaidSessionHardLimits() {
        let sessionManager = SessionManager.shared

        sessionManager.startScanStatsSessionIfNeeded(
            entitlementAtStart: FreeTrialTestSupport.entitlement()
        )

        for i in 1...10 {
            let result = sessionManager.scanStatsCount("TYPE-\(i)")
            assertScanStatsResult(result, is: .success)
        }

        let result11 = sessionManager.scanStatsCount("TYPE-11")
        assertScanStatsResult(
            result11,
            is: .maxTypesReached,
            "未購入体験中でも内部SSOTの種類数上限は守る想定"
        )
    }

    // MARK: - Kit 未購入体験（最初の1回だけ結果表示）

    func testKitTrialLimiter_AllowsOnlyOneReveal() {
        XCTAssertTrue(KitTrialLimiter.canRevealFirstResult())
        XCTAssertFalse(KitTrialLimiter.hasConsumedOneTimeReveal())

        let consumed = KitTrialLimiter.consumeOneTimeReveal()
        XCTAssertTrue(consumed, "最初の1回は消費成功する想定")

        XCTAssertFalse(KitTrialLimiter.canRevealFirstResult())
        XCTAssertTrue(KitTrialLimiter.hasConsumedOneTimeReveal())

        let consumedAgain = KitTrialLimiter.consumeOneTimeReveal()
        XCTAssertFalse(consumedAgain, "2回目以降は消費できない想定")
    }

    func testKitTrial_InternalProgressCanProceedBeforeFirstReveal() {
        let sessionManager = SessionManager.shared
        let kit = FreeTrialTestSupport.makeKitDefinition()

        sessionManager.upsertKit(
            kitId: kit.kitId,
            requiredCounts: kit.requiredCounts
        )

        sessionManager.startKitSessionIfNeeded(
            entitlementAtStart: FreeTrialTestSupport.entitlement()
        )

        sessionManager.selectKitId(kit.kitId)

        let r1 = sessionManager.scanKitComponent("ITEM-A")
        let r2 = sessionManager.scanKitComponent("ITEM-A")

        assertKitOutcome(r1, is: .progress)
        assertKitOutcome(r2, is: .progress)

        XCTAssertEqual(sessionManager.currentKitSession?.kitId, kit.kitId)
        XCTAssertEqual(sessionManager.currentKitSession?.scannedCounts["ITEM-A"], 2)

        XCTAssertTrue(KitTrialLimiter.canRevealFirstResult())
        XCTAssertFalse(KitTrialLimiter.hasConsumedOneTimeReveal())
    }

    func testKitTrial_FirstCompletedResultCanBeRevealedThenLocks() {
        let sessionManager = SessionManager.shared
        let kit = FreeTrialTestSupport.makeKitDefinition()

        sessionManager.upsertKit(
            kitId: kit.kitId,
            requiredCounts: kit.requiredCounts
        )

        sessionManager.startKitSessionIfNeeded(
            entitlementAtStart: FreeTrialTestSupport.entitlement()
        )
        sessionManager.selectKitId(kit.kitId)

        assertKitOutcome(sessionManager.scanKitComponent("ITEM-A"), is: .progress)
        assertKitOutcome(sessionManager.scanKitComponent("ITEM-A"), is: .progress)

        let finalResult = sessionManager.scanKitComponent("ITEM-B")
        assertKitOutcome(finalResult, is: .completedOK)

        XCTAssertTrue(KitTrialLimiter.canRevealFirstResult())

        let consumed = KitTrialLimiter.consumeOneTimeReveal()
        XCTAssertTrue(consumed)

        XCTAssertFalse(KitTrialLimiter.canRevealFirstResult())
        XCTAssertTrue(KitTrialLimiter.hasConsumedOneTimeReveal())
    }

    func testKitTrial_OverRequiredStillReturnsNGInternally() {
        let sessionManager = SessionManager.shared
        let kit = FreeTrialTestSupport.makeKitDefinition()

        sessionManager.upsertKit(
            kitId: kit.kitId,
            requiredCounts: kit.requiredCounts
        )

        sessionManager.startKitSessionIfNeeded(
            entitlementAtStart: FreeTrialTestSupport.entitlement()
        )
        sessionManager.selectKitId(kit.kitId)

        // ITEM-B は required=1 だが、ITEM-A が未完了なので 1回目は completedOK ではなく progress
        assertKitOutcome(sessionManager.scanKitComponent("ITEM-B"), is: .progress)

        let over = sessionManager.scanKitComponent("ITEM-B")

        if case .completedNG(let reason) = over {
            XCTAssertFalse(reason.isEmpty)
        } else {
            XCTFail("必要数超過は completedNG を返す想定")
        }
    }

    // MARK: - Helpers

    private enum ExpectedScanStatsResult {
        case success
        case maxTypesReached
        case maxTotalReached
        case noSession
    }

    private enum ExpectedKitOutcome {
        case progress
        case completedOK
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
