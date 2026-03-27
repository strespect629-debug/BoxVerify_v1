import SwiftUI

/// ✅ 正本：BackConfirm は「戻る操作を1か所に集約して通知するだけ」
/// - WorkExitDialog / WorkExitAction を再定義しない
/// - InteractivePopBlocker を再定義しない（別ファイルの正本を使う）
///
/// 使い方例：
/// .backConfirm {
///     requestExitConfirmation()
/// }
///
/// そして View 側で：
/// .workExitDialog(title:isPresented:onAction:) を表示する
struct BackConfirm: ViewModifier {

    let onAttemptExit: @MainActor () -> Void

    func body(content: Content) -> some View {
        content
            .navigationBarBackButtonHidden(true)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        onAttemptExit()
                    } label: {
                        Image(systemName: "chevron.left")
                            .imageScale(.large)
                    }
                    .accessibilityLabel("戻る")
                }
            }
            // ✅ スワイプ戻り開始を捕捉（戻り自体はキャンセルされる）
            .overlay(alignment: .topLeading) {
                InteractivePopBlocker {
                    onAttemptExit()
                }
                .frame(width: 0, height: 0)
            }
    }
}

extension View {
    /// ✅ 正本：BackConfirm を付与（戻るボタン＋スワイプ戻りの両方を同じハンドラへ）
    func backConfirm(onAttemptExit: @escaping @MainActor () -> Void) -> some View {
        modifier(BackConfirm(onAttemptExit: onAttemptExit))
    }
}
