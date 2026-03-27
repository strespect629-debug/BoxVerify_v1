import SwiftUI

@MainActor
struct ScanSuccessOverlay: View {

    let guideCenterYOffset: CGFloat

    var body: some View {
        GeometryReader { geo in

            // ScanFrameLayout のガイド枠と同じ比率（幅基準）
            let guideWidthRatio: CGFloat = 2.0 / 3.0
            let guideHeightRatio: CGFloat = 0.50

            let baseW = geo.size.width
            let w = baseW * guideWidthRatio
            let h = baseW * guideHeightRatio

            let cx = geo.size.width * 0.5
            let cy = (geo.size.height * 0.5 + guideCenterYOffset)

            // 枠の中心に表示（枠の中で見えるよう少し上寄せも可）
            let badgeY = cy

            ZStack {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 72, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(18)
                    .background(Color.black.opacity(0.35))
                    .clipShape(RoundedRectangle(cornerRadius: 18))
            }
            .position(x: cx, y: badgeY)
            .frame(width: w, height: h, alignment: .center)
        }
    }
}
