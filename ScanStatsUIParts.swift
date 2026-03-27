import SwiftUI

@MainActor
extension ScanStatsView {

    // MARK: - Layout parts

    func instructionCard() -> some View {
        let title = ScanUIStrings.scanPleaseTitle

        let message: String
        if !canUseScanStats {
            message = "\(ScanUIStrings.ScanStats.unpaidCardMessage)\n\(ScanUIStrings.confirmHint)"
        } else {
            message = "\(ScanUIStrings.ScanStats.paidCardMessage)\n\(ScanUIStrings.confirmHint)"
        }

        return VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.headline.weight(.semibold))
                .foregroundStyle(.white)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(3)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.black.opacity(0.38))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
        )
        .padding(.horizontal, 18)
    }

    func bottomOverlay() -> some View {
        VStack(spacing: 10) {
            if let s = sessionManager.currentScanStatsSession {
                // ✅ 購入済みは常に表示
                if canUseScanStats {
                    scanStatsOverlay(session: s)
                }
                // ✅ 未購入は「最初の5回まで」だけ集計表示
                else if s.totalScans <= 5 {
                    scanStatsOverlay(session: s)
                }
            }
        }
    }

    func floatingOverlay() -> some View {
        GeometryReader { geo in
            ZStack {
                // ✅ 確定ボタン
                ScanConfirmOverlay(
                    candidate: cameraManager.previewCode,
                    isEnabled: canConfirmScan,
                    onConfirm: {
                        let confirmed = cameraManager.confirmPreviewCode()
                        guard confirmed else { return }

                        ScanHaptics.shared.lightImpact()

                        // 🔥 ここが最重要修正
                        // onChange任せにせず、その場で処理へ橋渡しする
                        if let code = cameraManager.detectedCode?
                            .trimmingCharacters(in: .whitespacesAndNewlines),
                           !code.isEmpty {
                            handleDetectedCode(code)
                        }
                    }
                )
                .position(x: geo.size.width * 0.5, y: geo.size.height * 0.62)
                .allowsHitTesting(true)

                // ✅ 成功✅：枠の中心（手で隠れない）
                if showSuccessCheck {
                    ScanSuccessOverlay(guideCenterYOffset: guideCenterYOffset)
                        .transition(.opacity)
                        .animation(.easeInOut(duration: 0.12), value: showSuccessCheck)
                        .allowsHitTesting(false)
                }

                if toastPresenter.isPresented {
                    VStack {
                        Spacer()
                        toastView(text: toastPresenter.message)
                            .padding(.bottom, 120)
                    }
                    .transition(.opacity)
                    .animation(.easeInOut(duration: 0.15), value: toastPresenter.isPresented)
                    .allowsHitTesting(false)
                }
            }
        }
        .allowsHitTesting(true)
    }

    func scanStatsOverlay(session: ScanStatsSession) -> some View {
        let total = session.totalScans
        let types = session.codeCounts.count

        let top = session.codeCounts
            .sorted { $0.value > $1.value }
            .prefix(5)

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("集計")
                    .font(.headline)
                    .foregroundStyle(.white)

                Spacer()

                Text("Types \(types) / Total \(total)")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.80))
            }

            if top.isEmpty {
                Text("まだカウントがありません")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.75))
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(top.enumerated()), id: \.offset) { _, pair in
                        HStack {
                            Text(pair.key)
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.85))
                                .lineLimit(1)
                                .truncationMode(.middle)

                            Spacer()

                            Text("\(pair.value)")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.white)
                        }
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.black.opacity(0.35))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .padding(.horizontal, 18)
    }

    func toastView(text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(.white)
            .padding(.vertical, 10)
            .padding(.horizontal, 14)
            .background(Color.black.opacity(0.72))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, 18)
            .allowsHitTesting(false)
    }
}
