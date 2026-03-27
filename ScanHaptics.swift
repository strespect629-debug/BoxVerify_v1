import UIKit

/// 触覚（Haptics）を3画面で統一する
/// - View側で generator を @State で持つのを禁止し、ここに集約する
@MainActor
final class ScanHaptics {

    static let shared = ScanHaptics()

    private let impactLight = UIImpactFeedbackGenerator(style: .light)
    private let notification = UINotificationFeedbackGenerator()

    private init() {}

    func prepare() {
        impactLight.prepare()
        notification.prepare()
    }

    func lightImpact() {
        impactLight.prepare()
        impactLight.impactOccurred()
    }

    func success() {
        notification.prepare()
        notification.notificationOccurred(.success)
    }

    func error() {
        notification.prepare()
        notification.notificationOccurred(.error)
    }
}
