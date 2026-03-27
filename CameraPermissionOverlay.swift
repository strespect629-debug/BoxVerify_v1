import SwiftUI
import UIKit

@MainActor
struct CameraPermissionOverlay: View {

    let cameraError: String?

    var body: some View {
        Group {
            if let msg = cameraError, !msg.isEmpty {
                UnifiedEmptyStateCard(
                    title: "カメラがオフです",
                    message: "設定でカメラをONにしてください。\n\n\(msg)",
                    systemImage: "camera.slash",
                    action: .init(
                        title: "設定を開く",
                        handler: {
                            guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                            UIApplication.shared.open(url)
                        }
                    )
                )
                .padding(.horizontal, 18)
            } else {
                EmptyView()
            }
        }
    }
}
