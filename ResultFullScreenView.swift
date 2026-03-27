import SwiftUI

// MARK: - ResultFullScreenView（正本）
struct ResultFullScreenView: View {

    let title: String
    let message: String
    let kind: VerificationOutcomeKind

    /// OK のときだけ自動クローズ（秒）。nil なら自動クローズしない
    let autoCloseSeconds: Double?

    /// fullScreenCover 自動クローズ不安定対策：表示ごとに更新されるトークン
    let token: UUID

    /// 結果画面に表示できる追加情報（空なら非表示）
    let contextItems: [ContextItem]

    struct ContextItem: Identifiable, Hashable {
        let id = UUID()
        let label: String
        let value: String
        init(label: String, value: String) { self.label = label; self.value = value }
    }

    /// ✅ 閉じる時に呼ぶ（親が showingResult=false 等を必ず実行）
    let onClose: @MainActor () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var didClose: Bool = false
    @State private var autoCloseTask: Task<Void, Never>? = nil

    init(
        title: String,
        message: String,
        kind: VerificationOutcomeKind,
        /// ✅ 正本：デフォルトは nil（親がOK時だけ秒数を渡す）
        autoCloseSeconds: Double? = nil,
        token: UUID,
        contextItems: [ContextItem] = [],
        onClose: @escaping @MainActor () -> Void
    ) {
        self.title = title
        self.message = message
        self.kind = kind
        self.autoCloseSeconds = autoCloseSeconds
        self.token = token
        self.contextItems = contextItems
        self.onClose = onClose
    }

    var body: some View {
        ZStack {
            backgroundColor
                .ignoresSafeArea()

            // ✅ 中央コンテンツは「完全中央固定」
            centerContent
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .padding(.horizontal, 24)

            // ✅ ×ボタンは「別レイヤ」で右上固定（中央を押さない）
            closeButtonLayer
        }
        // ✅ tokenで「表示ごと」に必ずリセット＋自動クローズ予約を回す
        .task(id: token) {
            await resetAndSchedule()
        }
        .onDisappear {
            autoCloseTask?.cancel()
            autoCloseTask = nil
        }
    }

    private var closeButtonLayer: some View {
        VStack {
            HStack {
                Spacer()
                Button {
                    Task { @MainActor in
                        closeOnce()
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.95))
                        .padding(14)
                }
                .accessibilityLabel("閉じる")
                .padding(.trailing, 6)
                .padding(.top, 6) // ノッチ/角丸回避の最低限
            }
            Spacer()
        }
    }

    private var centerContent: some View {
        VStack(spacing: 18) {
            Image(systemName: iconName)
                .font(.system(size: 64, weight: .bold))
                .foregroundStyle(.white)

            Text(title)
                .font(.system(size: 34, weight: .heavy))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.8)

            Text(message)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
                .multilineTextAlignment(.center)

            if !contextItems.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(contextItems) { item in
                        HStack(alignment: .firstTextBaseline) {
                            Text(item.label)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.white.opacity(0.75))
                            Spacer()
                            Text(item.value)
                                .font(.caption.monospaced().weight(.semibold))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                }
                .padding(12)
                .background(Color.white.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .padding(.top, 6)
            }

            if kind != .ok {
                Button {
                    Task { @MainActor in
                        closeOnce()
                    }
                } label: {
                    Text("閉じる")
                        .font(.headline.bold())
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.white.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .padding(.top, 10)
                .padding(.horizontal, 26)
                .foregroundStyle(.white)
            } else {
                Text("OK")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.55))
                    .padding(.top, 18)
            }
        }
    }

    private var backgroundColor: Color {
        // ✅ 正本：全ケース明示（@unknown default 不使用）
        switch kind {
        case .ok: return Color.green
        case .ng: return Color.red
        case .notJudged: return Color.gray
        }
    }

    private var iconName: String {
        // ✅ 正本：全ケース明示（@unknown default 不使用）
        switch kind {
        case .ok: return "checkmark.circle.fill"
        case .ng: return "xmark.octagon.fill"
        case .notJudged: return "questionmark.circle.fill"
        }
    }

    @MainActor
    private func resetAndSchedule() async {
        // ✅ 表示ごとに必ず初期化（再利用時の「閉じない」を潰す）
        didClose = false

        autoCloseTask?.cancel()
        autoCloseTask = nil

        await scheduleAutoCloseIfNeeded()
    }

    @MainActor
    private func scheduleAutoCloseIfNeeded() async {
        guard kind == .ok else { return }
        guard didClose == false else { return }
        guard let seconds = autoCloseSeconds else { return }

        // ✅ 正本：sleepに渡す値は安全に作る（NaN/inf/負値を排除）
        guard seconds.isFinite else { return }
        let clamped = max(0.0, seconds)
        guard clamped > 0 else { return }

        let nanosDouble = clamped * 1_000_000_000.0
        let nanos = UInt64(min(nanosDouble, Double(UInt64.max)))

        autoCloseTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: nanos)

            // 古いTaskが生き残っても、ここで止める
            guard Task.isCancelled == false else { return }
            guard didClose == false else { return }

            closeOnce()
        }
    }

    @MainActor
    private func closeOnce() {
        guard didClose == false else { return }
        didClose = true

        autoCloseTask?.cancel()
        autoCloseTask = nil

        // ✅ 二重安全：親stateを戻してから、dismissも必ず呼ぶ
        onClose()
        dismiss()
    }
}
