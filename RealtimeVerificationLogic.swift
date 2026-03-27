import SwiftUI

@MainActor
extension RealtimeVerificationView {

    // MARK: - Menu actions

    func finishFromMenu() {
        toastPresenter.stop()
        detectionController.prepareForExit()
        sessionManager.finishCurrentSession(workType: .realtime)
        _ = sessionManager.setBaseCode(nil)
        dismiss()
    }

    func suspendFromMenu() {
        toastPresenter.stop()
        detectionController.prepareForExit()
        sessionManager.suspendCurrentSession(workType: .realtime)
        dismiss()
    }

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
                workType: .realtime,
                sessionManager: sessionManager,
                detectionController: detectionController,
                dismiss: dismiss
            )

        case .finish:
            detectionController.prepareForExit()
            sessionManager.finishCurrentSession(workType: .realtime)
            _ = sessionManager.setBaseCode(nil)
            dismiss()
        }
    }

    // MARK: - Trial

    func refreshTrialStatusAndEnforce() {
        let s = RealtimeTrialLimiter.status()
        trialStatus = s

        if isTrialMode && s.isExhausted {
            if sessionManager.baseCode != nil {
                _ = sessionManager.setBaseCode(nil)
            }
        }
    }

    // MARK: - Scan handling

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

        // Trial終了済み
        if isTrialMode && trialStatus.isExhausted {
            toastPresenter.show(
                text: ScanUIStrings.Realtime.trialExhaustedToast,
                duration: 0.9
            )

            detectionController.finishHandleAndResume(
                consumeDetected: true,
                pauseSeconds: 0.25,
                allowSameValue: false
            )
            return
        }

        // Base Code 未登録 → 登録
        if sessionManager.baseCode == nil {
            let ok = sessionManager.setBaseCode(raw)

            outcomeKind = ok ? .ok : .ng
            resultTitle = ok
                ? ScanUIStrings.Realtime.baseRegisteredTitle
                : ScanUIStrings.Realtime.cannotRegisterTitle
            resultMessage = ok
                ? ScanUIStrings.Realtime.baseRegisteredMessage
                : ScanUIStrings.Realtime.cannotRegisterMessage

            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 80_000_000)
                if ok {
                    ScanHaptics.shared.success()
                } else {
                    ScanHaptics.shared.error()
                }
            }

            detectionController.enterBlockingResult(consumeDetected: true)
            resultToken = UUID()
            showingResult = true
            return
        }

        // Base Code 異常
        guard let base = sessionManager.baseCode, !base.isEmpty else {
            outcomeKind = .notJudged
            resultTitle = ScanUIStrings.Realtime.baseMissingTitle
            resultMessage = ScanUIStrings.Realtime.baseMissingMessage

            detectionController.enterBlockingResult(consumeDetected: true)
            resultToken = UUID()
            showingResult = true
            return
        }

        // 照合
        let ok = (raw == base)

        outcomeKind = ok ? .ok : .ng
        resultTitle = ok ? ScanUIStrings.Realtime.okTitle : ScanUIStrings.Realtime.ngTitle
        resultMessage = ok ? ScanUIStrings.Realtime.okMessage : ScanUIStrings.Realtime.ngMessage

        sessionManager.recordRealtimeVerification(code: raw, outcome: outcomeKind)

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 80_000_000)
            if ok {
                ScanHaptics.shared.success()
            } else {
                ScanHaptics.shared.error()
            }
        }

        // Trial は1回で終了
        if isTrialMode {
            _ = RealtimeTrialLimiter.recordAttempt()
            _ = sessionManager.setBaseCode(nil)
            refreshTrialStatusAndEnforce()
        }

        detectionController.enterBlockingResult(consumeDetected: true)
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
