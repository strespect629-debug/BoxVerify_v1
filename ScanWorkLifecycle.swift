import SwiftUI

/// Work画面の lifecycle / onChange wiring を共通化する ViewModifier
/// - 目的: Viewごとの onAppear/onDisappear/scenePhase/showingMenu/showingResult/showingSuccess の順序差を根絶
@MainActor
struct ScanWorkLifecycleModifier: ViewModifier {

    @Environment(\.scenePhase) private var scenePhase

    let controller: ScanDetectionController

    let showingMenu: Bool
    let showingResult: Bool
    let showingSuccess: Bool

    func body(content: Content) -> some View {
        content
            .onAppear {
                // ✅ 必ず sync → onAppear の順
                controller.syncUIState(
                    menuShown: showingMenu,
                    resultShown: showingResult,
                    successShown: showingSuccess
                )
                controller.onAppear(scenePhase: scenePhase)
            }
            .onDisappear {
                controller.onDisappear()
            }
            .onChange(of: scenePhase) { _, newValue in
                controller.onScenePhaseChange(newValue)
            }
            .onChange(of: showingMenu) { _, newValue in
                controller.onMenuChange(isShown: newValue)
            }
            .onChange(of: showingResult) { _, newValue in
                controller.onResultChange(isShown: newValue)
            }
            .onChange(of: showingSuccess) { _, newValue in
                controller.onSuccessOverlayChange(isShown: newValue)
            }
    }
}

extension View {
    func scanWorkLifecycle(
        controller: ScanDetectionController,
        showingMenu: Bool,
        showingResult: Bool,
        showingSuccess: Bool
    ) -> some View {
        modifier(
            ScanWorkLifecycleModifier(
                controller: controller,
                showingMenu: showingMenu,
                showingResult: showingResult,
                showingSuccess: showingSuccess
            )
        )
    }
}
