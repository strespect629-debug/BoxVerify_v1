import SwiftUI

/// カメラスキャン範囲をユーザーに目視させるためのガイド枠
struct ScanRegionOverlay: View {

    /// 画面サイズに対する枠サイズ比率（お好みで微調整）
    var widthRatio: CGFloat = 0.72
    var heightRatio: CGFloat = 0.28

    /// 枠のRectを親へ返す（SwiftUI座標）
    var onRegionRectChanged: ((CGRect) -> Void)? = nil

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width * widthRatio
            let h = geo.size.height * heightRatio
            let rect = CGRect(
                x: (geo.size.width - w) / 2,
                y: (geo.size.height - h) / 2,
                width: w,
                height: h
            )

            ZStack {
                // 周辺を暗くして枠を強調（ユーザーが迷わない）
                Color.black.opacity(0.25)
                    .mask(
                        Rectangle()
                            .overlay(
                                RoundedRectangle(cornerRadius: 18)
                                    .frame(width: w, height: h)
                                    .blendMode(.destinationOut)
                            )
                            .compositingGroup()
                    )
                    .ignoresSafeArea()

                // 枠（角）
                RoundedRectangle(cornerRadius: 18)
                    .strokeBorder(Color.white.opacity(0.9), lineWidth: 2)
                    .frame(width: w, height: h)

                // 角のアクセント（見やすい）
                CornerMarks()
                    .stroke(Color.white.opacity(0.95), lineWidth: 4)
                    .frame(width: w, height: h)
            }
            .onAppear {
                onRegionRectChanged?(rect)
            }
            .onChange(of: geo.size) { _, _ in
                onRegionRectChanged?(rect)
            }
        }
        .allowsHitTesting(false)
    }
}

/// 角だけ太くするためのPath
private struct CornerMarks: Shape {
    func path(in rect: CGRect) -> Path {
        let corner: CGFloat = 22

        var p = Path()
        // 左上
        p.move(to: CGPoint(x: rect.minX, y: rect.minY + corner))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.minX + corner, y: rect.minY))

        // 右上
        p.move(to: CGPoint(x: rect.maxX - corner, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + corner))

        // 左下
        p.move(to: CGPoint(x: rect.minX, y: rect.maxY - corner))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX + corner, y: rect.maxY))

        // 右下
        p.move(to: CGPoint(x: rect.maxX - corner, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - corner))

        return p
    }
}

