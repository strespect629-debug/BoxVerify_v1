import SwiftUI

@MainActor
struct ScanConfirmOverlay: View {

    let candidate: String?
    let isEnabled: Bool
    let onConfirm: () -> Void

    private var normalizedCandidate: String? {
        guard let candidate else { return nil }
        let value = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    /// ✅ 候補があり、かつ上流も有効の時だけ押せる
    private var canTap: Bool {
        guard normalizedCandidate != nil else { return false }
        return isEnabled
    }

    private var displayText: String {
        if let normalizedCandidate {
            return normalizedCandidate
        }
        return "候補なし"
    }

    private var statusText: String {
        if canTap { return "有効" }
        return "無効"
    }

    var body: some View {
        VStack(spacing: 10) {
            VStack(spacing: 6) {
                Text(displayText)
                    .font(.caption.monospaced())
                    .foregroundStyle(.white.opacity(0.92))
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text(statusText)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.75))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color.black.opacity(0.45))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            Button {
                guard canTap else { return }
                onConfirm()
            } label: {
                Circle()
                    .fill(canTap ? Color.blue.opacity(0.92) : Color.gray.opacity(0.55))
                    .frame(width: 84, height: 84)
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(0.85), lineWidth: 3)
                    )
                    .shadow(radius: 8)
            }
            .buttonStyle(.plain)
            .disabled(!canTap)
            .accessibilityLabel("スキャン確定")
            .accessibilityHint("候補が出たら押して確定します")
        }
    }
}
