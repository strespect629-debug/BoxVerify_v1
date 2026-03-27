import SwiftUI

@MainActor
struct ScanStatsView: View {

    @ObservedObject var sessionManager = SessionManager.shared
    @ObservedObject var purchaseManager = PurchaseManager.shared
    @ObservedObject var cameraManager = CameraManager.shared

    @Environment(\.dismiss) var dismiss

    @StateObject var detectionController: ScanDetectionController

    @State var showingMenu: Bool = false

    @State var showingResult: Bool = false
    @State var outcomeKind: VerificationOutcomeKind = .notJudged
    @State var resultTitle: String = ""
    @State var resultMessage: String = ""
    @State var resultToken: UUID = UUID()

    @State var showSuccessCheck: Bool = false
    @State var successTask: Task<Void, Never>? = nil

    @StateObject var toastPresenter = ScanToastPresenter()

    @State var showingExitConfirm: Bool = false

    @State var showingFinalSummary: Bool = false
    @State var finalSummary: ScanStatsFinalSummary? = nil
    @State var pendingFinishAfterSummary: Bool = false

    init() {
        _detectionController = StateObject(
            wrappedValue: ScanDetectionController(cameraManager: .shared)
        )
    }

    var canUseScanStats: Bool {
        purchaseManager.scanStatsAccess.isAllowed
    }

    let guideCenterYOffset: CGFloat = -70
    let cardTopPadding: CGFloat = 26
    let bottomOverlayPadding: CGFloat = 26

    /// 🔥 修正ポイント
    /// 候補コードが見えているなら、メニュー/結果表示中でない限り確定ボタンを押せる
    /// detectionController.canHandleDetectedCode() には依存しすぎない
    var canConfirmScan: Bool {
        if showingMenu { return false }
        if showingResult { return false }
        if showSuccessCheck { return false }

        guard let p = cameraManager.previewCode?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !p.isEmpty else { return false }

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
                    instructionCard: { instructionCard() },
                    bottomTitle: { EmptyView() },
                    bottomOverlay: { bottomOverlay() },
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
                    Text(ScanUIStrings.ScanStats.screenTitle)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.white)

                    Text(ScanUIStrings.ScanStats.screenSubtitle)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.75))
                }
            }
        }
        .scanWorkToolbar(
            onBack: { requestExitConfirmation() },
            onMenu: { showingMenu = true }
        )
        .scanWorkLifecycle(
            controller: detectionController,
            showingMenu: showingMenu,
            showingResult: showingResult,
            showingSuccess: showSuccessCheck
        )
        .workExitDialog(
            title: "作業をどうしますか？",
            isPresented: $showingExitConfirm
        ) { action in
            handleExit(action)
        }
        .sheet(isPresented: $showingMenu) {
            NavigationStack {
                CompleteMenuView(
                    workType: .scanStats,
                    onFinish: {
                        beginFinishFlowWithFinalSummary()
                    },
                    onSuspend: {
                        teardownAndExit(finish: false)
                    }
                )
            }
        }
        .onAppear {
            let entitlementAtStart = EntitlementCapture.captureEntitlementAtStart(
                purchaseManager: purchaseManager
            )

            sessionManager.startScanStatsSessionIfNeeded(
                entitlementAtStart: entitlementAtStart
            )

            cameraManager.startSession()
            ScanHaptics.shared.prepare()
        }
        .onDisappear {
            stopEphemeralUIForDisappearOnly()
            toastPresenter.stop()
            cameraManager.stopSession()
        }
        .onChange(of: cameraManager.detectedCode) { _, newValue in
            handleDetectedCode(newValue)
        }
        .fullScreenCover(isPresented: $showingResult) {
            ResultFullScreenView(
                title: resultTitle,
                message: resultMessage,
                kind: outcomeKind,
                autoCloseSeconds: nil,
                token: resultToken
            ) {
                closeResult()
            }
        }
        .fullScreenCover(isPresented: $showingFinalSummary) {
            if let summary = finalSummary {
                ScanStatsFinalSummaryView(
                    summary: summary
                ) {
                    closeFinalSummaryAndFinishIfNeeded()
                }
            } else {
                ResultFullScreenView(
                    title: ScanUIStrings.ScanStats.noSessionTitle,
                    message: ScanUIStrings.ScanStats.noSessionMessage,
                    kind: .notJudged,
                    autoCloseSeconds: nil,
                    token: UUID()
                ) {
                    showingFinalSummary = false
                    pendingFinishAfterSummary = false
                }
            }
        }
    }
}
