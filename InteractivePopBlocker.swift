import SwiftUI
import UIKit

/// スワイプ戻り（interactivePopGesture）をフックして、
/// pop をキャンセル → onPopAttempt を呼ぶためのブロッカー。
///
/// 使い方:
///   InteractivePopBlocker { requestExitConfirmation() }
///     .frame(width: 0, height: 0)
struct InteractivePopBlocker: UIViewControllerRepresentable {

    let onPopAttempt: () -> Void

    func makeUIViewController(context: Context) -> UIViewController {
        let vc = UIViewController()
        vc.view.backgroundColor = .clear
        context.coordinator.attach(to: vc)
        return vc
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        context.coordinator.attach(to: uiViewController)
        context.coordinator.onPopAttempt = onPopAttempt
    }

    static func dismantleUIViewController(_ uiViewController: UIViewController, coordinator: Coordinator) {
        coordinator.detach()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onPopAttempt: onPopAttempt)
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {

        var onPopAttempt: () -> Void

        private weak var nav: UINavigationController?
        private weak var popGesture: UIGestureRecognizer?

        private weak var originalGestureDelegate: UIGestureRecognizerDelegate?

        private var isAttached: Bool = false

        init(onPopAttempt: @escaping () -> Void) {
            self.onPopAttempt = onPopAttempt
        }

        func attach(to viewController: UIViewController) {
            guard let nav = viewController.navigationController else { return }
            guard let gesture = nav.interactivePopGestureRecognizer else { return }

            // 既に同じnavへattach済みなら何もしない
            if isAttached, self.nav === nav, self.popGesture === gesture { return }

            // 既存のattachがあれば一旦外す（navが変わったケース）
            detach()

            self.nav = nav
            self.popGesture = gesture

            // 元delegate退避 → 自分がdelegateになる
            self.originalGestureDelegate = gesture.delegate
            gesture.delegate = self

            // popGestureが無効化される事故を避ける（念のため）
            gesture.isEnabled = true

            isAttached = true
        }

        func detach() {
            guard isAttached else { return }
            if let gesture = popGesture {
                // 元に戻す（副作用残骸根絶）
                gesture.delegate = originalGestureDelegate
            }
            nav = nil
            popGesture = nil
            originalGestureDelegate = nil
            isAttached = false
        }

        // MARK: - UIGestureRecognizerDelegate

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            // ✅ ここで false を返すと pop が開始されない（=キャンセル）
            onPopAttempt()
            return false
        }
    }
}
