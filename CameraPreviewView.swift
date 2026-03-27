import SwiftUI
import UIKit
@preconcurrency import AVFoundation

struct CameraPreviewView: UIViewRepresentable {

    @ObservedObject var manager: CameraManager
    let guideCenterYOffset: CGFloat

    /// 見た目は以前の幅に戻す
    private let guideWidthRatio: CGFloat = 2.0 / 3.0
    private let guideHeightRatio: CGFloat = 0.50
    private let guideCornerRadius: CGFloat = 18

    /// バーコード用に、検出ROIだけ見た目の枠より広げる
    private let roiExpandX: CGFloat = 28
    private let roiExpandY: CGFloat = 18

    init(manager: CameraManager, guideCenterYOffset: CGFloat = 0) {
        self.manager = manager
        self.guideCenterYOffset = guideCenterYOffset
    }

    final class Coordinator {
        weak var guideLayer: CAShapeLayer?
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

        var videoPreviewLayer: AVCaptureVideoPreviewLayer {
            layer as! AVCaptureVideoPreviewLayer
        }
    }

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.backgroundColor = .black
        view.videoPreviewLayer.videoGravity = .resizeAspectFill

        view.videoPreviewLayer.session = manager.captureSession
        manager.attachPreviewLayer(view.videoPreviewLayer)

        let guide = CAShapeLayer()
        guide.name = "boxverify.guide"
        guide.fillColor = UIColor.clear.cgColor
        guide.strokeColor = UIColor.white.withAlphaComponent(0.65).cgColor
        guide.lineWidth = 2
        view.layer.addSublayer(guide)

        context.coordinator.guideLayer = guide

        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        uiView.videoPreviewLayer.session = manager.captureSession
        manager.attachPreviewLayer(uiView.videoPreviewLayer)

        // ✅ iOS 17以降の非推奨警告対策
        if let connection = uiView.videoPreviewLayer.connection {
            if #available(iOS 17.0, *) {
                if connection.isVideoRotationAngleSupported(90) {
                    connection.videoRotationAngle = 90
                }
            } else {
                if connection.isVideoOrientationSupported {
                    connection.videoOrientation = .portrait
                }
            }
        }

        let bounds = uiView.bounds
        guard bounds.width > 0, bounds.height > 0 else { return }

        // 見た目のガイド枠
        let guideWidth = bounds.width * guideWidthRatio
        let guideHeight = bounds.width * guideHeightRatio

        let guideX = max(0, min((bounds.width - guideWidth) / 2, bounds.width - guideWidth))
        let guideY = max(0, min((bounds.height - guideHeight) / 2 + guideCenterYOffset, bounds.height - guideHeight))

        let guideRect = CGRect(
            x: guideX,
            y: guideY,
            width: guideWidth,
            height: guideHeight
        )

        let guideLayer: CAShapeLayer
        if let existing = context.coordinator.guideLayer {
            guideLayer = existing
        } else {
            let created = CAShapeLayer()
            created.name = "boxverify.guide"
            created.fillColor = UIColor.clear.cgColor
            created.strokeColor = UIColor.white.withAlphaComponent(0.65).cgColor
            created.lineWidth = 2
            uiView.layer.addSublayer(created)
            context.coordinator.guideLayer = created
            guideLayer = created
        }

        guideLayer.path = UIBezierPath(
            roundedRect: guideRect,
            cornerRadius: guideCornerRadius
        ).cgPath

        // バーコード用に、検出範囲だけ少し広くする
        var roiRect = guideRect.insetBy(dx: -roiExpandX, dy: -roiExpandY)

        if roiRect.minX < 0 {
            roiRect.origin.x = 0
        }
        if roiRect.minY < 0 {
            roiRect.origin.y = 0
        }
        if roiRect.maxX > bounds.width {
            roiRect.size.width = bounds.width - roiRect.origin.x
        }
        if roiRect.maxY > bounds.height {
            roiRect.size.height = bounds.height - roiRect.origin.y
        }

        let normalizedROI = uiView.videoPreviewLayer.metadataOutputRectConverted(
            fromLayerRect: roiRect
        )
        manager.setRectOfInterest(normalizedROI)

        // ガイド枠そのものも CameraManager に渡す
        manager.updateGuideRectForFiltering(guideRect, in: uiView.videoPreviewLayer)
    }

    static func dismantleUIView(_ uiView: PreviewView, coordinator: Coordinator) {
        uiView.videoPreviewLayer.session = nil
        coordinator.guideLayer?.removeFromSuperlayer()
        coordinator.guideLayer = nil
    }
}
