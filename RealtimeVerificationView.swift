import SwiftUI

@MainActor
struct RealtimeVerificationView: View {

    @ObservedObject var sessionManager = SessionManager.shared
    @ObservedObject var purchaseManager = PurchaseManager.shared
    @ObservedObject var cameraManager = CameraManager.shared

    @Environment(\.dismiss) var dismiss

    @State var showingMenu: Bool = false
    @State var showingResult: Bool = false
    @State var showingExitConfirm: Bool = false

    @State var outcomeKind: VerificationOutcomeKind = .notJudged
    @State var resultTitle: String = ""
    @State var resultMessage: String = ""
    @State var resultToken: UUID = UUID()

    @State var trialStatus: RealtimeTrialLimiter.Status = RealtimeTrialLimiter.status()

    @StateObject var toastPresenter = ScanToastPresenter()
    @StateObject var detectionController: ScanDetectionController

    init() {
        _detectionController = StateObject(
            wrappedValue: ScanDetectionController(cameraManager: .shared)
        )
    }

    var canUseRealtime: Bool { purchaseManager.realtimeAccess.isAllowed }
    var isTrialMode: Bool { !canUseRealtime }

    let guideCenterYOffset: CGFloat = -70
    let cardTopPadding: CGFloat = 26
    let bottomOverlayPadding: CGFloat = 26

    /// ✅ ScanStats と同じ思想に統一
    /// 候補コードが見えているなら、メニュー/結果表示中でない限り確定ボタンを押せる
    /// detectionController.canHandleDetectedCode() には依存しすぎない
    var canConfirmScan: Bool {
        if showingMenu { return false }
        if showingResult { return false }

        guard let p = cameraManager.previewCode?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !p.isEmpty else { return false }

        if isTrialMode && trialStatus.isExhausted { return false }

        return true
    }

    var body: some View {
        ZStack {
            if let err = cameraManager.cameraError, !err.isEmpty {
                CameraPermissionOverlay(cameraError: err)
            } else {
                ScanFrameLayout(
                    cameraManager: cameraManager,
                    guideCenterYOffset: guideCenterYOffset,
                    cardTopPadding: cardTopPadding,
                    bottomOverlayPadding: bottomOverlayPadding,
                    instructionCard: { instructionCardThin() },
                    bottomTitle: { EmptyView() },
                    bottomOverlay: { realtimeInfoOverlay() },
                    floatingOverlay: { floatingOverlay() }
                )

                InteractivePopBlocker {
                    requestExitConfirmation()
                }
                .frame(width: 0, height: 0)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 2) {
                    Text(ScanUIStrings.Realtime.screenTitle)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.white)

                    Text(ScanUIStrings.Realtime.screenSubtitle)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.75))
                }
            }
        }
        .scanWorkToolbar(
            onBack: { requestExitConfirmation() },
            onMenu: { showingMenu = true }
        )
        .workExitDialog(
            title: "作業をどうしますか？",
            isPresented: $showingExitConfirm
        ) { action in
            handleExit(action)
        }
        .scanWorkLifecycle(
            controller: detectionController,
            showingMenu: showingMenu,
            showingResult: showingResult,
            showingSuccess: false
        )
        .onChange(of: showingMenu) { _, isShown in
            if isShown {
                toastPresenter.stop()
            }
        }
        .onChange(of: showingResult) { _, isShown in
            if isShown {
                toastPresenter.stop()
            } else {
                ScanHaptics.shared.prepare()
            }
        }
        .sheet(isPresented: $showingMenu) {
            NavigationStack {
                CompleteMenuView(
                    workType: .realtime,
                    onFinish: { finishFromMenu() },
                    onSuspend: { suspendFromMenu() }
                )
            }
        }
        .onAppear {
            let entitlementAtStart = EntitlementCapture.captureEntitlementAtStart(
                purchaseManager: purchaseManager
            )

            sessionManager.startRealtimeSessionIfNeeded(
                entitlementAtStart: entitlementAtStart
            )

            cameraManager.startSession()
            ScanHaptics.shared.prepare()

            RealtimeTrialLimiter.resetIfNewDay()
            refreshTrialStatusAndEnforce()
        }
        .onDisappear {
            toastPresenter.stop()
            cameraManager.stopSession()
        }
        .onChange(of: cameraManager.detectedCode) { _, newValue in
            handleDetectedCode(newValue)
        }
        .fullScreenCover(isPresented: $showingResult) {
            let autoSeconds: Double? = (outcomeKind == .ok) ? 1.2 : nil

            ResultFullScreenView(
                title: resultTitle,
                message: resultMessage,
                kind: outcomeKind,
                autoCloseSeconds: autoSeconds,
                token: resultToken
            ) {
                closeResult()
            }
        }
    }
}
