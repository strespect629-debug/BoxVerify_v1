import SwiftUI
import Combine

@MainActor
final class ScanDetectionController: ObservableObject {

    @Published private(set) var isDetectionSuppressed: Bool = false

    private var isSceneActive: Bool = true
    private var isMenuShown: Bool = false
    private var isResultShown: Bool = false
    private var isSuccessShown: Bool = false

    private let cameraManager: CameraManager

    private let defaultPauseSeconds: Double = 0.18
    private let menuClosePauseSeconds: Double = 0.12

    private var resumeTask: Task<Void, Never>? = nil

    init(cameraManager: CameraManager) {
        self.cameraManager = cameraManager
    }

    // MARK: - Sync
    func syncUIState(menuShown: Bool, resultShown: Bool, successShown: Bool) {
        isMenuShown = menuShown
        isResultShown = resultShown
        isSuccessShown = successShown
    }

    // MARK: - Lifecycle

    /// 🔥 初回は必ず起動＋抑止解除
    func onAppear(scenePhase: ScenePhase) {
        isSceneActive = (scenePhase == .active)

        cameraManager.startSession()

        // 🔥 ここ重要：抑止を確実に解除
        cameraManager.setOutputSuppressed(false)
        isDetectionSuppressed = false
    }

    func onDisappear() {
        cancelResumeTask()

        cameraManager.setOutputSuppressed(true)
        cameraManager.consumeDetectedCode()
        cameraManager.stopSession()

        isDetectionSuppressed = true
    }

    func onScenePhaseChange(_ newPhase: ScenePhase) {

        if newPhase == .active {
            isSceneActive = true

            // 🔥 必ず再起動
            cameraManager.startSession()

            cameraManager.setOutputSuppressed(false)
            isDetectionSuppressed = false
            return
        }

        if newPhase == .inactive {
            isSceneActive = false

            cameraManager.setOutputSuppressed(true)
            isDetectionSuppressed = true
            return
        }

        if newPhase == .background {
            isSceneActive = false
            suppressAndStopForBackground()
            return
        }

        isSceneActive = false
        suppressAndStopForBackground()
    }

    // MARK: - UI State

    func onMenuChange(isShown: Bool) {
        isMenuShown = isShown

        if isShown {
            suppressOutput(consumeDetected: true)
        } else {
            // 🔥 必ず再起動
            cameraManager.startSession()

            finishAndResume(
                consumeDetected: true,
                pauseSeconds: menuClosePauseSeconds,
                allowSameValue: true
            )
        }
    }

    func onResultChange(isShown: Bool, consumeWhenShown: Bool = false) {
        isResultShown = isShown

        if isShown {
            suppressOutput(consumeDetected: consumeWhenShown)
        } else {
            cameraManager.startSession()

            finishAndResume(
                consumeDetected: true,
                pauseSeconds: defaultPauseSeconds,
                allowSameValue: true
            )
        }
    }

    func onSuccessOverlayChange(isShown: Bool) {
        isSuccessShown = isShown

        if isShown {
            suppressOutput(consumeDetected: true)
        } else {
            cameraManager.startSession()

            finishAndResume(
                consumeDetected: true,
                pauseSeconds: defaultPauseSeconds,
                allowSameValue: true
            )
        }
    }

    // MARK: - Detection

    func canHandleDetectedCode() -> Bool {
        if !isSceneActive { return false }
        if isMenuShown { return false }
        if isResultShown { return false }
        if isSuccessShown { return false }
        if isDetectionSuppressed { return false }
        return true
    }

    func beginHandleDetectedCode() {
        cancelResumeTask()

        isDetectionSuppressed = true
        cameraManager.setOutputSuppressed(true)
    }

    func finishHandleAndResume(
        consumeDetected: Bool = true,
        pauseSeconds: Double = 0.18,
        allowSameValue: Bool = true
    ) {
        finishAndResume(
            consumeDetected: consumeDetected,
            pauseSeconds: pauseSeconds,
            allowSameValue: allowSameValue
        )
    }

    func enterBlockingResult(consumeDetected: Bool = false) {
        cancelResumeTask()

        isDetectionSuppressed = true
        cameraManager.setOutputSuppressed(true)

        if consumeDetected {
            cameraManager.consumeDetectedCode()
        }
    }

    func prepareForExit() {
        cancelResumeTask()

        isDetectionSuppressed = true
        cameraManager.setOutputSuppressed(true)
        cameraManager.consumeDetectedCode()
        cameraManager.stopSession()
    }

    // MARK: - Internals

    private func cancelResumeTask() {
        resumeTask?.cancel()
        resumeTask = nil
    }

    private func suppressOutput(consumeDetected: Bool) {
        cancelResumeTask()

        isDetectionSuppressed = true
        cameraManager.setOutputSuppressed(true)

        if consumeDetected {
            cameraManager.consumeDetectedCode()
        }
    }

    private func finishAndResume(
        consumeDetected: Bool,
        pauseSeconds: Double,
        allowSameValue: Bool
    ) {
        cancelResumeTask()

        if consumeDetected {
            cameraManager.consumeDetectedCode()
        }

        cameraManager.pauseOutput(seconds: pauseSeconds)
        cameraManager.prepareForNextScan(allowSameValue: allowSameValue)

        resumeTask = Task { @MainActor in
            if Task.isCancelled { return }

            try? await Task.sleep(nanoseconds: UInt64(pauseSeconds * 1_000_000_000))

            if Task.isCancelled { return }

            // 🔥 必ず再起動
            self.cameraManager.startSession()

            self.cameraManager.setOutputSuppressed(false)
            self.isDetectionSuppressed = false
        }
    }

    private func suppressAndStopForBackground() {
        cancelResumeTask()

        cameraManager.setOutputSuppressed(true)
        cameraManager.consumeDetectedCode()
        cameraManager.stopSession()

        isDetectionSuppressed = true
    }
}
