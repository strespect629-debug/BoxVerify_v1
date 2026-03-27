import SwiftUI

@MainActor
extension KitCheckView {

    // MARK: - Exit

    func requestExitConfirmation() {
        if showingResult { return }
        if showingMenu { return }
        showingExitConfirm = true
    }

    func handleExit(_ action: WorkExitAction) {
        showingExitConfirm = false
        toastPresenter.stop()

        switch action {
        case .suspend:
            ScanWorkExitHandler.exit(
                action: .suspend,
                workType: .kit,
                sessionManager: sessionManager,
                detectionController: detectionController,
                dismiss: dismiss
            )

        case .finish:
            ScanWorkExitHandler.exit(
                action: .finish,
                workType: .kit,
                sessionManager: sessionManager,
                detectionController: detectionController,
                dismiss: dismiss
            )
        }
    }

    func finishOrSuspendFromMenu(finish: Bool) {
        toastPresenter.stop()

        ScanWorkExitHandler.exit(
            action: finish ? .finish : .suspend,
            workType: .kit,
            sessionManager: sessionManager,
            detectionController: detectionController,
            dismiss: dismiss
        )
    }

    // MARK: - Scan

    func handleDetectedCode(_ code: String?) {
        guard let raw = code?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else { return }

        if showingMenu { return }
        if showingResult { return }

        let isDirectConfirmedCode = (cameraManager.detectedCode == raw)

        guard detectionController.canHandleDetectedCode() || isDirectConfirmedCode else {
            return
        }

        detectionController.beginHandleDetectedCode()

        // 二重処理防止（onConfirm直呼び + onChange）
        cameraManager.consumeDetectedCode()

        guard let session = sessionManager.currentKitSession else {
            presentKitResult(
                kind: .notJudged,
                title: ScanUIStrings.Kit.notJudgedTitle,
                message: ScanUIStrings.Kit.noSessionMessage
            )
            return
        }

        // ✅ 無課金でも Kit ID 選択と内部進行は行う
        if !isKitAllowed {

            // Kit ID 選択
            if session.kitId == nil {
                sessionManager.selectKitId(raw)
                ScanHaptics.shared.lightImpact()
                toastPresenter.show(
                    text: ScanUIStrings.Kit.unpaidKitIdToast,
                    duration: 0.9
                )

                detectionController.finishHandleAndResume(
                    consumeDetected: true,
                    pauseSeconds: 0.18,
                    allowSameValue: true
                )
                return
            }

            // 構成品スキャン（内部進行）
            let outcome = sessionManager.scanKitComponent(raw)

            switch outcome {
            case .progress:
                ScanHaptics.shared.lightImpact()
                toastPresenter.show(
                    text: ScanUIStrings.Kit.unpaidToast,
                    duration: 0.9
                )

                detectionController.finishHandleAndResume(
                    consumeDetected: true,
                    pauseSeconds: 0.18,
                    allowSameValue: true
                )

            case .completedOK:
                if KitTrialLimiter.canRevealFirstResult() {
                    _ = KitTrialLimiter.consumeOneTimeReveal()
                    ScanHaptics.shared.success()

                    presentKitResult(
                        kind: .ok,
                        title: ScanUIStrings.Kit.okTitle,
                        message: "\(ScanUIStrings.Kit.okMessage)\n\(ScanUIStrings.Kit.trialResultSuffix)"
                    )
                } else {
                    ScanHaptics.shared.lightImpact()
                    toastPresenter.show(
                        text: ScanUIStrings.Kit.unpaidToast,
                        duration: 0.9
                    )

                    detectionController.finishHandleAndResume(
                        consumeDetected: true,
                        pauseSeconds: 0.18,
                        allowSameValue: true
                    )
                }

            case .completedNG(let reason):
                if KitTrialLimiter.canRevealFirstResult() {
                    _ = KitTrialLimiter.consumeOneTimeReveal()
                    ScanHaptics.shared.error()

                    presentKitResult(
                        kind: .ng,
                        title: ScanUIStrings.Realtime.ngTitle,
                        message: "\(reason)\n\(ScanUIStrings.Kit.trialResultSuffix)"
                    )
                } else {
                    ScanHaptics.shared.lightImpact()
                    toastPresenter.show(
                        text: ScanUIStrings.Kit.unpaidToast,
                        duration: 0.9
                    )

                    detectionController.finishHandleAndResume(
                        consumeDetected: true,
                        pauseSeconds: 0.18,
                        allowSameValue: true
                    )
                }

            case .noSession:
                presentKitResult(
                    kind: .notJudged,
                    title: ScanUIStrings.Kit.notJudgedTitle,
                    message: ScanUIStrings.Kit.noSessionMessage
                )
            }

            return
        }

        // ✅ 購入済み
        if session.kitId == nil {
            sessionManager.selectKitId(raw)
            ScanHaptics.shared.lightImpact()

            detectionController.finishHandleAndResume(
                consumeDetected: true,
                pauseSeconds: 0.16,
                allowSameValue: true
            )
            return
        }

        let outcome = sessionManager.scanKitComponent(raw)

        switch outcome {
        case .progress:
            ScanHaptics.shared.lightImpact()

            detectionController.finishHandleAndResume(
                consumeDetected: true,
                pauseSeconds: 0.14,
                allowSameValue: true
            )

        case .completedOK:
            ScanHaptics.shared.success()
            presentKitResult(
                kind: .ok,
                title: ScanUIStrings.Kit.okTitle,
                message: ScanUIStrings.Kit.okMessage
            )

        case .completedNG(let reason):
            ScanHaptics.shared.error()
            presentKitResult(
                kind: .ng,
                title: ScanUIStrings.Realtime.ngTitle,
                message: reason
            )

        case .noSession:
            presentKitResult(
                kind: .notJudged,
                title: ScanUIStrings.Kit.notJudgedTitle,
                message: ScanUIStrings.Kit.noSessionMessage
            )
        }
    }

    func presentKitResult(kind: VerificationOutcomeKind, title: String, message: String) {
        toastPresenter.stop()

        detectionController.enterBlockingResult(consumeDetected: true)

        resultKind = kind
        resultTitle = title
        resultMessage = message
        resultToken = UUID()
        showingResult = true
    }

    // MARK: - Result close

    func closeResult() {
        showingResult = false
        toastPresenter.stop()
        ScanHaptics.shared.prepare()

        detectionController.finishHandleAndResume(
            consumeDetected: true,
            pauseSeconds: 0.18,
            allowSameValue: true
        )
    }
}
