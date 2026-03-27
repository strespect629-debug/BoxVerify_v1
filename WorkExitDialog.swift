import SwiftUI

// MARK: - Work Exit Action（正本）
enum WorkExitAction: Equatable {
    case suspend
    case finish
}

// MARK: - WorkExitDialog Modifier（正本）
extension View {

    /// 離脱時の確認（保存して中断 / 終了して破棄 / キャンセル）
    func workExitDialog(
        title: String,
        isPresented: Binding<Bool>,
        onSelect: @escaping @MainActor (WorkExitAction) -> Void
    ) -> some View {
        self.confirmationDialog(title, isPresented: isPresented, titleVisibility: .visible) {

            Button("保存して中断") {
                onSelect(.suspend)
            }

            Button("終了して破棄", role: .destructive) {
                onSelect(.finish)
            }

            Button("キャンセル", role: .cancel) { }

        } message: {
            Text("作業選択に戻る前に、作業データをどうするか選んでください。")
        }
    }
}
