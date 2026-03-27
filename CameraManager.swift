import SwiftUI
import Combine
import QuartzCore
@preconcurrency import AVFoundation

@MainActor
final class CameraManager: NSObject, ObservableObject, AVCaptureMetadataOutputObjectsDelegate {

    static let shared = CameraManager()

    /// 確定後に View へ流す（onChangeで処理に入る）
    @Published var detectedCode: String? = nil

    /// 手動確定用の候補
    @Published var previewCode: String? = nil

    @Published var cameraError: String? = nil
    @Published private(set) var captureSession: AVCaptureSession? = nil

    private let sessionQueue = DispatchQueue(label: "boxverify.camera.sessionQueue")

    private weak var previewLayer: AVCaptureVideoPreviewLayer?
    private weak var metadataOutputRef: AVCaptureMetadataOutput?

    /// ROI（metadata座標）
    private var rectOfInterest: CGRect = .init(x: 0, y: 0, width: 1, height: 1)

    /// ガイド枠（preview layer座標）
    private var guideRectInLayer: CGRect = .zero

    private var manualSuppressed: Bool = false
    private var pausedUntil: CFTimeInterval = 0

    /// 手動確定方式では同一値ロックは confirm に適用しない
    private var lastEmittedValue: String? = nil
    private var lastEmittedAt: CFTimeInterval = 0

    private var lockedMissingSince: CFTimeInterval? = nil
    private let rearmAfterNotSeenSeconds: CFTimeInterval = 0.40

    private var sameValueRearmArmed: Bool = false
    private var sameValueRearmTarget: String? = nil
    private var sameValueRearmMissingSince: CFTimeInterval? = nil
    private let sameValueRearmAfterNotSeenSeconds: CFTimeInterval = 0.20

    private struct Candidate {
        var firstSeenAt: CFTimeInterval
        var lastSeenAt: CFTimeInterval
        var seenCount: Int
    }
    private var candidates: [String: Candidate] = [:]

    /// バーコードも拾いやすいように軽め
    private let stableSeconds: CFTimeInterval = 0.01
    private let stableSeenCount: Int = 1
    private let minIntervalBetweenEmits: CFTimeInterval = 0.12

    private var confirmCooldownUntil: CFTimeInterval = 0
    private let confirmCooldownSeconds: CFTimeInterval = 0.10

    private var isConfiguringSession: Bool = false

    /// フォーカス用
    private var videoDevice: AVCaptureDevice?
    private var lastFocusSetAt: CFTimeInterval = 0

    private final class UncheckedSendableBox<T>: @unchecked Sendable {
        let value: T
        init(_ value: T) { self.value = value }
    }

    private override init() {
        super.init()
    }

    deinit {
        // deinit では stop を呼ばない
    }

    // MARK: - Public API

    func attachPreviewLayer(_ layer: AVCaptureVideoPreviewLayer) {
        previewLayer = layer
        layer.videoGravity = .resizeAspectFill

        if let session = captureSession {
            layer.session = session
        } else {
            layer.session = nil
        }
    }

    /// 正本：引数ラベル無し
    /// CameraPreviewView から渡されたROIを metadata output に適用
    func setRectOfInterest(_ normalized: CGRect) {
        rectOfInterest = clampNormalizedRect(normalized)
        metadataOutputRef?.rectOfInterest = rectOfInterest
    }

    /// ガイド枠（見た目の枠）を保持
    func updateGuideRectForFiltering(_ rect: CGRect, in layer: AVCaptureVideoPreviewLayer) {
        guideRectInLayer = rect
        attachPreviewLayer(layer)
        requestFocusToGuideCenterIfNeeded()
    }

    /// detectedCode を nil にするだけ
    func consumeDetectedCode() {
        detectedCode = nil
    }

    /// 出力抑止（delegate側で emit 自体を止める）
    func setOutputSuppressed(_ suppressed: Bool) {
        manualSuppressed = suppressed
        if suppressed {
            clearPreviewState()
            candidates.removeAll()
        }
    }

    /// 一時停止（秒）
    func pauseOutput(seconds: Double) {
        guard seconds.isFinite else { return }
        let s = max(0.0, seconds)
        if s <= 0 { return }
        let now = CACurrentMediaTime()
        pausedUntil = max(pausedUntil, now + s)
    }

    /// 次スキャン準備：候補リセット
    func prepareForNextScan(allowSameValue: Bool) {
        candidates.removeAll()
        clearPreviewState()

        lockedMissingSince = nil
        lastEmittedAt = CACurrentMediaTime() - minIntervalBetweenEmits

        if allowSameValue, let locked = lastEmittedValue {
            sameValueRearmArmed = true
            sameValueRearmTarget = locked
            sameValueRearmMissingSince = nil
        } else {
            sameValueRearmArmed = false
            sameValueRearmTarget = nil
            sameValueRearmMissingSince = nil
        }
    }

    /// 候補を確定して detectedCode を発火する（手動確定モード）
    @discardableResult
    func confirmPreviewCode() -> Bool {
        let now = CACurrentMediaTime()
        if now < confirmCooldownUntil { return false }

        let candidate = normalizedPreviewCandidate()
        guard let code = candidate, !code.isEmpty else { return false }

        confirmCooldownUntil = now + confirmCooldownSeconds

        // onChange が同値で発火しない事故防止
        detectedCode = nil
        detectedCode = code

        // 候補表示はいったん消す
        clearPreviewState()
        candidates.removeAll()

        // 手動確定後も同じコードをすぐ再候補にできるようにロック解除
        unlockSameValueForManualConfirm(now: now)

        return true
    }

    func startSession() {
        cameraError = nil

        if let existing = captureSession {
            previewLayer?.session = existing

            let boxed = UncheckedSendableBox(existing)
            sessionQueue.async {
                let session = boxed.value
                if !session.isRunning {
                    session.startRunning()
                }
            }
            return
        }

        if isConfiguringSession { return }
        isConfiguringSession = true

        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            startAuthorizedSession()

        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.isConfiguringSession = false
                    if granted {
                        self.startSession()
                    } else {
                        self.cameraError = "カメラへのアクセスが許可されていません。設定から許可してください。"
                    }
                }
            }

        case .denied, .restricted:
            isConfiguringSession = false
            cameraError = "カメラへのアクセスが許可されていません。設定から許可してください。"

        @unknown default:
            isConfiguringSession = false
            cameraError = "カメラの権限状態を確認できません。"
        }
    }

    func stopSession() {
        guard let old = captureSession else { return }

        captureSession = nil
        detectedCode = nil
        clearPreviewState()
        metadataOutputRef = nil
        isConfiguringSession = false
        videoDevice = nil

        if let previewLayer {
            previewLayer.session = nil
        }

        resetGatesOnStop()

        let boxed = UncheckedSendableBox(old)
        sessionQueue.async {
            let session = boxed.value
            if session.isRunning {
                session.stopRunning()
            }
        }
    }

    // MARK: - Internal

    private func unlockSameValueForManualConfirm(now: CFTimeInterval) {
        lastEmittedValue = nil
        lockedMissingSince = nil

        sameValueRearmArmed = false
        sameValueRearmTarget = nil
        sameValueRearmMissingSince = nil

        lastEmittedAt = now
    }

    private func resetGatesOnStop() {
        manualSuppressed = false
        pausedUntil = 0

        lastEmittedValue = nil
        lastEmittedAt = 0
        lockedMissingSince = nil

        sameValueRearmArmed = false
        sameValueRearmTarget = nil
        sameValueRearmMissingSince = nil

        candidates.removeAll()
        confirmCooldownUntil = 0
        clearPreviewState()
    }

    private func clearPreviewState() {
        previewCode = nil
    }

    private func normalizedPreviewCandidate() -> String? {
        if let previewCode {
            let value = previewCode.trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty { return value }
        }
        return nil
    }

    private func startAuthorizedSession() {
        let session = AVCaptureSession()
        session.beginConfiguration()
        session.sessionPreset = .high

        guard let device = AVCaptureDevice.default(for: .video) else {
            cameraError = "カメラデバイスが見つかりません。"
            session.commitConfiguration()
            isConfiguringSession = false
            return
        }
        videoDevice = device

        do {
            let input = try AVCaptureDeviceInput(device: device)
            if session.canAddInput(input) {
                session.addInput(input)
            } else {
                cameraError = "カメラ入力をセッションに追加できません。"
                session.commitConfiguration()
                isConfiguringSession = false
                return
            }
        } catch {
            cameraError = "カメラ入力の初期化に失敗しました。"
            session.commitConfiguration()
            isConfiguringSession = false
            return
        }

        let output = AVCaptureMetadataOutput()
        if session.canAddOutput(output) {
            session.addOutput(output)
        } else {
            cameraError = "コード読み取り出力をセッションに追加できません。"
            session.commitConfiguration()
            isConfiguringSession = false
            return
        }

        output.setMetadataObjectsDelegate(self, queue: .main)

        /// BoxVerifyで使うコード種だけに限定
        let desired: [AVMetadataObject.ObjectType] = [
            .qr,
            .ean8, .ean13,
            .code39, .code93, .code128,
            .upce,
            .itf14,
            .dataMatrix,
            .pdf417,
            .aztec
        ]
        output.metadataObjectTypes = desired.filter { output.availableMetadataObjectTypes.contains($0) }

        /// CameraPreviewView側から更新されるROIを適用
        output.rectOfInterest = rectOfInterest

        session.commitConfiguration()

        metadataOutputRef = output
        captureSession = session
        isConfiguringSession = false

        if let previewLayer {
            previewLayer.session = session
        }

        configureDeviceForScanning(device)

        let boxed = UncheckedSendableBox(session)
        sessionQueue.async {
            let s = boxed.value
            if !s.isRunning {
                s.startRunning()
            }
        }
    }

    private func configureDeviceForScanning(_ device: AVCaptureDevice) {
        sessionQueue.async {
            do {
                try device.lockForConfiguration()
                defer { device.unlockForConfiguration() }

                if device.isFocusModeSupported(.continuousAutoFocus) {
                    device.focusMode = .continuousAutoFocus
                }

                if device.isExposureModeSupported(.continuousAutoExposure) {
                    device.exposureMode = .continuousAutoExposure
                }

                if device.isAutoFocusRangeRestrictionSupported {
                    device.autoFocusRangeRestriction = .near
                }

                if device.isSmoothAutoFocusSupported {
                    device.isSmoothAutoFocusEnabled = true
                }

                if device.isLowLightBoostSupported {
                    device.automaticallyEnablesLowLightBoostWhenAvailable = true
                }
            } catch {
                // 設定失敗でも落とさない
            }
        }
    }

    private func requestFocusToGuideCenterIfNeeded() {
        let now = CACurrentMediaTime()
        if now - lastFocusSetAt < 0.45 { return }
        lastFocusSetAt = now

        guard let previewLayer else { return }
        guard guideRectInLayer != .zero else { return }
        guard let device = videoDevice else { return }

        let center = CGPoint(x: guideRectInLayer.midX, y: guideRectInLayer.midY)
        let devicePoint = previewLayer.captureDevicePointConverted(fromLayerPoint: center)

        sessionQueue.async {
            do {
                try device.lockForConfiguration()
                defer { device.unlockForConfiguration() }

                if device.isFocusPointOfInterestSupported,
                   device.isFocusModeSupported(.continuousAutoFocus) {
                    device.focusPointOfInterest = devicePoint
                    device.focusMode = .continuousAutoFocus
                }

                if device.isExposurePointOfInterestSupported,
                   device.isExposureModeSupported(.continuousAutoExposure) {
                    device.exposurePointOfInterest = devicePoint
                    device.exposureMode = .continuousAutoExposure
                }
            } catch {
                // ignore
            }
        }
    }

    // MARK: - AVCaptureMetadataOutputObjectsDelegate

    func metadataOutput(
        _ output: AVCaptureMetadataOutput,
        didOutput metadataObjects: [AVMetadataObject],
        from connection: AVCaptureConnection
    ) {
        let now = CACurrentMediaTime()

        if manualSuppressed { return }
        if now < pausedUntil { return }

        var acceptedValues: [String] = []

        for obj in metadataObjects {
            guard let readable = obj as? AVMetadataMachineReadableCodeObject else { continue }
            guard let raw = readable.stringValue else { continue }

            let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else { continue }

            /// ガイド枠の中にあるコードだけ採用
            if let previewLayer,
               guideRectInLayer != .zero,
               let transformed = previewLayer.transformedMetadataObject(for: readable) as? AVMetadataMachineReadableCodeObject {
                let center = CGPoint(x: transformed.bounds.midX, y: transformed.bounds.midY)
                if guideRectInLayer.contains(center) {
                    acceptedValues.append(value)
                }
            } else {
                acceptedValues.append(value)
            }
        }

        if sameValueRearmArmed,
           let target = sameValueRearmTarget,
           lastEmittedValue == target {

            if acceptedValues.contains(target) {
                sameValueRearmMissingSince = nil
            } else {
                if sameValueRearmMissingSince == nil {
                    sameValueRearmMissingSince = now
                }
                if let since = sameValueRearmMissingSince,
                   (now - since) >= sameValueRearmAfterNotSeenSeconds {
                    lastEmittedValue = nil
                    sameValueRearmArmed = false
                    sameValueRearmTarget = nil
                    sameValueRearmMissingSince = nil
                }
            }
        }

        if let locked = lastEmittedValue {
            if acceptedValues.contains(locked) {
                lockedMissingSince = nil
            } else {
                if lockedMissingSince == nil {
                    lockedMissingSince = now
                }
                if let since = lockedMissingSince,
                   (now - since) > rearmAfterNotSeenSeconds {
                    lastEmittedValue = nil
                    lockedMissingSince = nil
                }
            }
        }

        /// 枠内にコードが無ければ即候補解除
        if acceptedValues.isEmpty {
            purgeOldCandidates(now: now)
            clearPreviewState()
            return
        }

        /// 同一値の重複はつぶすが、順序は残す
        var uniqueOrdered: [String] = []
        var seen = Set<String>()
        for value in acceptedValues where !seen.contains(value) {
            seen.insert(value)
            uniqueOrdered.append(value)
        }

        /// 複数見えても、前回候補がまだ含まれていれば優先
        let selectedValue: String
        if let previewCode, uniqueOrdered.contains(previewCode) {
            selectedValue = previewCode
        } else {
            selectedValue = uniqueOrdered[0]
        }

        updateCandidate(value: selectedValue, now: now)
        purgeOldCandidates(now: now)

        /// 候補は即表示（保持しない）
        previewCode = selectedValue

        guard let c = candidates[selectedValue] else { return }

        let stableByTime = (now - c.firstSeenAt) >= stableSeconds
        let stableByCount = c.seenCount >= stableSeenCount

        if !(stableByTime && stableByCount) {
            return
        }

        if now - lastEmittedAt < minIntervalBetweenEmits { return }
    }

    private func updateCandidate(value: String, now: CFTimeInterval) {
        if var c = candidates[value] {
            c.lastSeenAt = now
            c.seenCount += 1
            candidates[value] = c
        } else {
            candidates[value] = Candidate(
                firstSeenAt: now,
                lastSeenAt: now,
                seenCount: 1
            )
        }
    }

    private func purgeOldCandidates(now: CFTimeInterval) {
        let threshold: CFTimeInterval = 0.60
        var toRemove: [String] = []

        for (k, c) in candidates {
            if now - c.lastSeenAt > threshold {
                toRemove.append(k)
            }
        }

        for k in toRemove {
            candidates.removeValue(forKey: k)
        }
    }

    private func clampNormalizedRect(_ rect: CGRect) -> CGRect {
        let x = max(0, min(1, rect.origin.x))
        let y = max(0, min(1, rect.origin.y))
        var w = max(0, min(1 - x, rect.size.width))
        var h = max(0, min(1 - y, rect.size.height))

        if w < 0.05 { w = 0.05 }
        if h < 0.05 { h = 0.05 }

        return CGRect(x: x, y: y, width: w, height: h)
    }
}
