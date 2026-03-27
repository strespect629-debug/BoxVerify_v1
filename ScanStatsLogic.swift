import SwiftUI

@MainActor
extension ScanStatsView {

    // MARK: - Exit

    func requestExitConfirmation() {
        if showingResult { return }
        if showingMenu { return }
        if showingFinalSummary { return }

        showingExitConfirm = true
    }

    func handleExit(_ action: WorkExitAction) {
        showingExitConfirm = false
        toastPresenter.stop()

        switch action {
        case .suspend:
            teardownAndExit(finish: false)

        case .finish:
            beginFinishFlowWithFinalSummary()
        }
    }

    // MARK: - Finish flow

    func beginFinishFlowWithFinalSummary() {
        toastPresenter.stop()
        successTask?.cancel()
        successTask = nil
        showSuccessCheck = false

        // sheet競合を避ける
        showingMenu = false

        // 検出停止（ただし session データはまだ消さない）
        detectionController.prepareForExit()

        // 未購入時は最終集計画面を出さず、そのまま終了
        guard canUseScanStats else {
            pendingFinishAfterSummary = false
            finalSummary = nil
            teardownAndExit(finish: true)
            return
        }

        guard let s = sessionManager.currentScanStatsSession else {
            finalSummary = nil
            pendingFinishAfterSummary = false
            showingFinalSummary = true
            return
        }

        finalSummary = ScanStatsFinalSummary.from(session: s)
        pendingFinishAfterSummary = true
        showingFinalSummary = true
    }

    func closeFinalSummaryAndFinishIfNeeded() {
        showingFinalSummary = false

        guard pendingFinishAfterSummary else { return }
        pendingFinishAfterSummary = false

        detectionController.prepareForExit()
        sessionManager.finishCurrentSession(workType: .scanStats)
        dismiss()
    }

    // MARK: - Detected Code

    func handleDetectedCode(_ code: String?) {
        guard let raw = code?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else { return }

        if showingMenu { return }
        if showingResult { return }
        if showingFinalSummary { return }

        let isDirectConfirmedCode = (cameraManager.detectedCode == raw)

        guard detectionController.canHandleDetectedCode() || isDirectConfirmedCode else {
            return
        }

        detectionController.beginHandleDetectedCode()

        // 二重処理防止
        cameraManager.consumeDetectedCode()

        guard sessionManager.currentScanStatsSession != nil else {
            outcomeKind = .notJudged
            resultTitle = ScanUIStrings.ScanStats.noSessionTitle
            resultMessage = ScanUIStrings.ScanStats.noSessionMessage

            detectionController.enterBlockingResult(
                consumeDetected: true
            )

            resultToken = UUID()
            showingResult = true
            return
        }

        // MARK: 未購入：最初の5回まで体験可能
        if !canUseScanStats {
            let result = sessionManager.scanStatsCount(raw)

            switch result {
            case .success:
                if ScanStatsTrialLimiter.canShowPreview() {
                    _ = ScanStatsTrialLimiter.recordPreviewUse()

                    ScanHaptics.shared.lightImpact()
                    detectionController.enterBlockingResult(
                        consumeDetected: true
                    )
                    showSuccessCheckNowAndResume()

                    toastPresenter.show(
                        text: ScanUIStrings.ScanStats.unpaidToast,
                        duration: 0.9
                    )
                } else {
                    ScanHaptics.shared.lightImpact()
                    toastPresenter.show(
                        text: ScanUIStrings.ScanStats.unpaidLockedToast,
                        duration: 0.9
                    )

                    detectionController.finishHandleAndResume(
                        consumeDetected: true,
                        pauseSeconds: 0.18,
                        allowSameValue: true
                    )
                }

            case .maxTypesReached:
                outcomeKind = .ng
                resultTitle = ScanUIStrings.ScanStats.limitTitle
                resultMessage = ScanUIStrings.ScanStats.maxTypesMessage

                detectionController.enterBlockingResult(
                    consumeDetected: true
                )

                resultToken = UUID()
                showingResult = true

            case .maxTotalReached:
                outcomeKind = .ng
                resultTitle = ScanUIStrings.ScanStats.limitTitle
                resultMessage = ScanUIStrings.ScanStats.maxTotalMessage

                detectionController.enterBlockingResult(
                    consumeDetected: true
                )

                resultToken = UUID()
                showingResult = true

            case .noSession:
                outcomeKind = .notJudged
                resultTitle = ScanUIStrings.ScanStats.noSessionTitle
                resultMessage = ScanUIStrings.ScanStats.noSessionMessage

                detectionController.enterBlockingResult(
                    consumeDetected: true
                )

                resultToken = UUID()
                showingResult = true
            }

            return
        }

        // MARK: 購入済み
        let result = sessionManager.scanStatsCount(raw)

        switch result {
        case .success:
            ScanHaptics.shared.lightImpact()

            detectionController.enterBlockingResult(
                consumeDetected: true
            )
            showSuccessCheckNowAndResume()

        case .maxTypesReached:
            outcomeKind = .ng
            resultTitle = ScanUIStrings.ScanStats.limitTitle
            resultMessage = ScanUIStrings.ScanStats.maxTypesMessage

            detectionController.enterBlockingResult(
                consumeDetected: true
            )

            resultToken = UUID()
            showingResult = true

        case .maxTotalReached:
            outcomeKind = .ng
            resultTitle = ScanUIStrings.ScanStats.limitTitle
            resultMessage = ScanUIStrings.ScanStats.maxTotalMessage

            detectionController.enterBlockingResult(
                consumeDetected: true
            )

            resultToken = UUID()
            showingResult = true

        case .noSession:
            outcomeKind = .notJudged
            resultTitle = ScanUIStrings.ScanStats.noSessionTitle
            resultMessage = ScanUIStrings.ScanStats.noSessionMessage

            detectionController.enterBlockingResult(
                consumeDetected: true
            )

            resultToken = UUID()
            showingResult = true
        }
    }

    // MARK: - Result close

    func closeResult() {
        showingResult = false
        toastPresenter.stop()
        ScanHaptics.shared.prepare()
    }

    // MARK: - Success Check

    func showSuccessCheckNowAndResume() {
        successTask?.cancel()

        showSuccessCheck = false
        showSuccessCheck = true

        successTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 650_000_000)
            showSuccessCheck = false

            detectionController.finishHandleAndResume(
                consumeDetected: true,
                pauseSeconds: 0.18,
                allowSameValue: true
            )

            ScanHaptics.shared.prepare()
        }
    }

    // MARK: - Cleanup

    func stopEphemeralUIForDisappearOnly() {
        toastPresenter.stop()

        successTask?.cancel()
        successTask = nil
    }

    // MARK: - Teardown

    func teardownAndExit(finish: Bool) {
        toastPresenter.stop()

        successTask?.cancel()
        successTask = nil
        showSuccessCheck = false

        detectionController.prepareForExit()

        if finish {
            sessionManager.finishCurrentSession(workType: .scanStats)
        } else {
            sessionManager.suspendCurrentSession(workType: .scanStats)
        }

        dismiss()
    }
}
