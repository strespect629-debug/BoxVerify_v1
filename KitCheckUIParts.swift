import SwiftUI

@MainActor
extension KitCheckView {

    // MARK: - Instruction Card

    func kitInstructionCardThin() -> some View {
        let title: String
        let message: String

        if !isKitAllowed {
            title = ScanUIStrings.Kit.unpaidTitle
            message = "\(ScanUIStrings.Kit.unpaidMessage)\n\(ScanUIStrings.confirmHint)"
        } else if sessionManager.currentKitSession == nil {
            title = ScanUIStrings.Kit.cannotStartTitle
            message = ScanUIStrings.Kit.cannotStartMessage
        } else if sessionManager.currentKitSession?.kitId == nil {
            title = ScanUIStrings.Kit.needKitIdTitle
            message = "\(ScanUIStrings.Kit.needKitIdMessage)\n\(ScanUIStrings.confirmHint)"
        } else {
            title = ScanUIStrings.scanPleaseTitle
            message = ScanUIStrings.confirmHint
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

    // MARK: - Bottom Overlay

    func kitBottomOverlay() -> some View {
        VStack(spacing: 10) {
            if let session = sessionManager.currentKitSession {
                kitStatsOverlay(session: session)
            } else {
                kitEmptyStatsOverlay()
            }
        }
    }

    // MARK: - Floating Overlay

    func kitFloatingOverlay() -> some View {
        GeometryReader { geo in
            ZStack {

                ScanConfirmOverlay(
                    candidate: cameraManager.previewCode,
                    isEnabled: canConfirmScan
                ) {
                    let confirmed = cameraManager.confirmPreviewCode()
                    guard confirmed else { return }

                    ScanHaptics.shared.lightImpact()

                    if let code = cameraManager.detectedCode?
                        .trimmingCharacters(in: .whitespacesAndNewlines),
                       !code.isEmpty {
                        handleDetectedCode(code)
                    }
                }
                .position(x: geo.size.width * 0.5, y: geo.size.height * 0.62)
                .allowsHitTesting(true)

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

    // MARK: - Toast

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

    // MARK: - Stats Overlay

    func kitStatsOverlay(session: KitSession) -> some View {
        let totalRequired = session.requiredCounts.values.reduce(0, +)

        let effectiveScanned = session.requiredCounts.keys.reduce(0) { partial, code in
            let required = session.requiredCounts[code] ?? 0
            let scanned = session.scannedCounts[code] ?? 0
            return partial + min(required, scanned)
        }

        let remaining = max(0, totalRequired - effectiveScanned)

        let missing: [(code: String, remaining: Int)] = session.requiredCounts.compactMap { (code, req) in
            let scanned = session.scannedCounts[code] ?? 0
            let r = max(0, req - scanned)
            return r > 0 ? (code, r) : nil
        }
        .sorted {
            if $0.remaining == $1.remaining {
                return $0.code < $1.code
            }
            return $0.remaining > $1.remaining
        }
        .prefix(5)
        .map { $0 }

        let kitIdText = session.kitId?.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedKitId = (kitIdText?.isEmpty == false) ? kitIdText! : "Kit未選択"

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Kit 集計")
                    .font(.headline)
                    .foregroundStyle(.white)

                Spacer()

                Text(normalizedKitId)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.75))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            ProgressView(
                value: totalRequired == 0 ? 0 : Double(effectiveScanned),
                total: max(1, Double(totalRequired))
            )
            .tint(.white)

            HStack {
                Text("合計")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.75))

                Spacer()

                Text("\(effectiveScanned) / \(max(1, totalRequired))（残り \(remaining)）")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.85))
            }

            if session.requiredCounts.isEmpty {
                Divider().overlay(Color.white.opacity(0.18))

                Text("まだ構成品がありません")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.75))
            } else if !missing.isEmpty {
                Divider().overlay(Color.white.opacity(0.18))

                Text("不足（上位）")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.85))

                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(missing.enumerated()), id: \.offset) { _, item in
                        HStack {
                            Text(item.code)
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.9))
                                .lineLimit(1)
                                .truncationMode(.middle)

                            Spacer()

                            Text("残り \(item.remaining)")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.75))
                        }
                    }
                }
            } else {
                Divider().overlay(Color.white.opacity(0.18))

                Text("必要な構成品はすべて揃っています")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.85))
            }

            if !isKitAllowed {
                Text("無課金でも進捗は確認できます。結果表示の継続利用には Kit プランが必要です。")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.68))
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

    // MARK: - Empty Stats Overlay

    func kitEmptyStatsOverlay() -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Kit 集計")
                    .font(.headline)
                    .foregroundStyle(.white)

                Spacer()

                Text("Kit未選択")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.75))
            }

            Text("まだキットの読み込みがありません")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.80))

            if !isKitAllowed {
                Text("無課金でもスキャンして進められます")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.68))
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
}
