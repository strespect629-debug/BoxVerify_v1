import SwiftUI

@MainActor
extension RealtimeVerificationView {

    // MARK: - Instruction card

    func instructionCardThin() -> some View {
        if isTrialMode && trialStatus.isExhausted {
            return AnyView(
                UnifiedEmptyStateCard(
                    title: ScanUIStrings.Realtime.trialExhaustedTitle,
                    message: ScanUIStrings.Realtime.trialExhaustedMessage,
                    systemImage: ScanUIStrings.qrViewfinderSF
                )
            )
        }

        let title: String
        let message: String

        if sessionManager.baseCode == nil {
            title = ScanUIStrings.Realtime.baseCodeTitle
            message = "\(ScanUIStrings.Realtime.baseCodeMessage)\n\(ScanUIStrings.confirmHint)"
        } else {
            title = ScanUIStrings.Realtime.verifyTitle
            message = "\(ScanUIStrings.Realtime.verifyMessage)\n\(ScanUIStrings.confirmHint)"
        }

        return AnyView(
            VStack(alignment: .leading, spacing: 6) {
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
        )
    }

    // MARK: - Bottom overlay（Base Codeカード）

    func realtimeInfoOverlay() -> some View {
        let baseText: String = {
            guard let base = sessionManager.baseCode, !base.isEmpty else { return "未登録" }
            return base
        }()

        let scans: Int = sessionManager.currentRealtimeSession?.verificationScans ?? 0

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("Base Code")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.85))

                Text(baseText)
                    .font(.caption.monospaced())
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            HStack(spacing: 8) {
                Text("照合回数")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.85))

                Text("\(scans)")
                    .font(.caption.monospaced().weight(.semibold))
                    .foregroundStyle(.white)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.black.opacity(0.35))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .padding(.horizontal, 18)
    }

    // MARK: - Floating overlay（無印丸ボタン + Toast）

    func floatingOverlay() -> some View {
        GeometryReader { geo in
            ZStack {
                ScanConfirmOverlay(
                    candidate: cameraManager.previewCode,
                    isEnabled: canConfirmScan
                ) {
                    let confirmed = cameraManager.confirmPreviewCode()
                    guard confirmed else { return }

                    ScanHaptics.shared.lightImpact()

                    // onChange任せにせず、その場で処理へ橋渡し
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
