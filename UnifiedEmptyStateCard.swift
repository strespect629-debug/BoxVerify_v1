import SwiftUI

// MARK: - UnifiedEmptyStateCard (空状態カード共通)
struct UnifiedEmptyStateCard: View {

    struct Action {
        let title: String
        let handler: @MainActor () async -> Void

        init(title: String, handler: @escaping @MainActor () async -> Void) {
            self.title = title
            self.handler = handler
        }
    }

    let title: String
    let message: String
    let systemImage: String
    let footnote: String?
    let action: Action?

    @State private var isRunning: Bool = false

    init(
        title: String,
        message: String,
        systemImage: String,
        footnote: String? = nil,
        action: Action? = nil
    ) {
        self.title = title
        self.message = message
        self.systemImage = systemImage
        self.footnote = footnote
        self.action = action
    }

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 42))
                .foregroundStyle(.white.opacity(0.85))
                .accessibilityHidden(true)

            Text(title)
                .font(.headline)
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.85))
                .multilineTextAlignment(.center)

            if let footnote {
                Text(footnote)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .padding(.top, 2)
            }

            if let action {
                Button {
                    guard !isRunning else { return }
                    isRunning = true
                    Task { @MainActor in
                        await action.handler()
                        isRunning = false
                    }
                } label: {
                    HStack(spacing: 10) {
                        if isRunning {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Text(isRunning ? "処理中…" : action.title)
                            .font(.headline)
                    }
                    .foregroundStyle(.black)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .padding(.top, 6)
                .disabled(isRunning)
                .accessibilityLabel(action.title)
                .accessibilityHint("空状態を解消するための操作を実行します")
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(Color.black.opacity(0.70))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .contain)
    }
}
