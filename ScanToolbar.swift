import SwiftUI

/// 3画面で toolbar を統一する
/// - View側で toolbar を直書きするのを禁止し、modifier 経由に統一
struct ScanWorkToolbar: ViewModifier {

    let onBack: () -> Void
    let onMenu: () -> Void

    func body(content: Content) -> some View {
        content
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: onBack) {
                        Image(systemName: "chevron.left")
                            .imageScale(.large)
                    }
                    .accessibilityLabel("戻る")
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: onMenu) {
                        Image(systemName: "ellipsis.circle")
                            .imageScale(.large)
                    }
                    .accessibilityLabel("メニュー")
                }
            }
    }
}

extension View {
    func scanWorkToolbar(
        onBack: @escaping () -> Void,
        onMenu: @escaping () -> Void
    ) -> some View {
        modifier(ScanWorkToolbar(onBack: onBack, onMenu: onMenu))
    }
}
