import SwiftUI

@MainActor
struct KitCheckView: View {

    // ❗️分割するので private 禁止（extension から参照する）
    @ObservedObject var sessionManager = SessionManager.shared
    @ObservedObject var purchaseManager = PurchaseManager.shared
    @ObservedObject var cameraManager = CameraManager.shared

    @Environment(\.dismiss) var dismiss

    // ✅ UI state
    @State var showingMenu: Bool = false
    @State var showingResult: Bool = false
    @State var showingExitConfirm: Bool = false

    // ✅ Result state
    @State var resultKind: VerificationOutcomeKind = .notJudged
    @State var resultTitle: String = ""
    @State var resultMessage: String = ""
    @State var resultToken: UUID = UUID()

    // ✅ Toast
    @StateObject var toastPresenter = ScanToastPresenter()

    // ✅ 検出抑止SSOT
    @StateObject var detectionController: ScanDetectionController

    init() {
        _detectionController = StateObject(
            wrappedValue: ScanDetectionController(cameraManager: .shared)
        )
    }

    var isKitAllowed: Bool { purchaseManager.kitAccess.isAllowed }

    // ✅ Layout constants
    let guideCenterYOffset: CGFloat = -70
    let cardTopPadding: CGFloat = 26
    let bottomOverlayPadding: CGFloat = 26

    /// 候補コードが見えていれば押せる
    var canConfirmScan: Bool {
        if showingMenu { return false }
        if showingResult { return false }

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
                    instructionCard: { kitInstructionCardThin() },
                    bottomTitle: { EmptyView() },
                    bottomOverlay: { kitBottomOverlay() },
                    floatingOverlay: { kitFloatingOverlay() }
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
                    Text(ScanUIStrings.Kit.screenTitle)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.white)

                    Text(ScanUIStrings.Kit.screenSubtitle)
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
            showingSuccess: false
        )
        .workExitDialog(
            title: "作業をどうしますか？",
            isPresented: $showingExitConfirm
        ) { action in
            handleExit(action)
        }
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
                    workType: .kit,
                    onFinish: { finishOrSuspendFromMenu(finish: true) },
                    onSuspend: { finishOrSuspendFromMenu(finish: false) }
                )
            }
        }
        .onAppear {
            let entitlementAtStart = EntitlementCapture.captureEntitlementAtStart(
                purchaseManager: purchaseManager
            )

            sessionManager.startKitSessionIfNeeded(
                entitlementAtStart: entitlementAtStart
            )

            cameraManager.startSession()
            ScanHaptics.shared.prepare()
        }
        .onDisappear {
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
                kind: resultKind,
                autoCloseSeconds: (resultKind == .ok ? 1.2 : nil),
                token: resultToken
            ) {
                closeResult()
            }
        }
    }
}
