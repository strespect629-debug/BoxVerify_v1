import Foundation
import Combine
/// ResultFullScreenView の表示状態を View から分離し、全画面で統一する
/// - Viewは「present(...)」「dismiss()」だけ呼ぶ
@MainActor
final class ScanResultPresenter: ObservableObject {

    struct Payload: Equatable {
        let kind: VerificationOutcomeKind
        let title: String
        let message: String
        let autoCloseSeconds: Double?
    }

    @Published var isPresented: Bool = false
    @Published var payload: Payload = .init(kind: .notJudged, title: "", message: "", autoCloseSeconds: nil)

    /// ResultFullScreenView の安定化（表示ごとに必ず更新して .task(id:) を走らせる）
    @Published var token: UUID = UUID()

    func present(
        kind: VerificationOutcomeKind,
        title: String,
        message: String,
        autoCloseSeconds: Double? = nil
    ) {
        payload = .init(kind: kind, title: title, message: message, autoCloseSeconds: autoCloseSeconds)
        token = UUID()
        isPresented = true
    }

    func dismiss() {
        isPresented = false
    }
}
