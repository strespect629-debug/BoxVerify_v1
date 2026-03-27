import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

// MARK: - DiagnosticsView（正本：注入専用）
struct DiagnosticsView: View {

    let diagnosticsText: String

    @Environment(\.dismiss) private var dismiss

    @State private var toast: String? = nil
    @State private var toastTask: Task<Void, Never>? = nil

    private var displayText: String {
        diagnosticsText.isEmpty ? "（診断情報がありません）" : diagnosticsText
    }

    var body: some View {
        VStack(spacing: 12) {
            ScrollView {
                Text(displayText)
                    .font(.system(.footnote, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }

            HStack(spacing: 10) {
                Button("コピー") {
                    copyToPasteboard()
                }
                .disabled(diagnosticsText.isEmpty || !canCopy)

                Button("閉じる") {
                    dismiss()
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
        .navigationTitle("Diagnostics")
        .navigationBarTitleDisplayMode(.inline)
        .overlay(alignment: .top) {
            if let toast {
                Text(toast)
                    .font(.caption.bold())
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())
                    .padding(.top, 12)
                    .transition(.opacity)
                    .accessibilityLabel(toast)
            }
        }
        .onDisappear {
            toastTask?.cancel()
            toastTask = nil
        }
    }

    private var canCopy: Bool {
        #if canImport(UIKit)
        return true
        #else
        return false
        #endif
    }

    @MainActor
    private func copyToPasteboard() {
        #if canImport(UIKit)
        UIPasteboard.general.string = diagnosticsText
        showToast("コピーしました")
        #else
        showToast("この環境ではコピーできません")
        #endif
    }

    @MainActor
    private func showToast(_ msg: String) {
        toastTask?.cancel()
        toastTask = nil

        withAnimation(.easeInOut(duration: 0.15)) {
            toast = msg
        }

        toastTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            withAnimation(.easeInOut(duration: 0.15)) {
                toast = nil
            }
        }
    }
}
