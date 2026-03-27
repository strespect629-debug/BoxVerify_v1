import SwiftUI

@MainActor
struct ScanWorkExitHandler {

    static func exit(
        action: WorkExitAction,
        workType: WorkType,
        sessionManager: SessionManager,
        detectionController: ScanDetectionController,
        dismiss: DismissAction
    ) {
        // ✅ suspend / finish のみ離脱準備
        detectionController.prepareForExit()

        switch action {
        case .suspend:
            sessionManager.suspendCurrentSession(workType: workType)
            dismiss()

        case .finish:
            sessionManager.finishCurrentSession(workType: workType)
            dismiss()
        }
    }
}
