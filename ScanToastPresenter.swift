import SwiftUI
import Combine

/// ✅ Toast表示のTask管理を一本化（残骸・cancel漏れ根絶）
@MainActor
final class ScanToastPresenter: ObservableObject {

    @Published var isPresented: Bool = false
    @Published var message: String = ""

    private var task: Task<Void, Never>? = nil

    func show(text: String, duration: Double = 0.9) {
        stop()

        message = text
        isPresented = true

        let ns = UInt64(max(0.1, duration) * 1_000_000_000)

        task = Task { @MainActor in
            try? await Task.sleep(nanoseconds: ns)
            isPresented = false
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        isPresented = false
    }
}
