import AVFoundation
import Combine
import CoreImage
import Photos
import UIKit

final class CameraSessionController: NSObject, ObservableObject {
    let session = AVCaptureSession()

    @Published var authorizationStatus: AVAuthorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
    @Published var compositionResult: CompositionResult?
    @Published var latestImage: UIImage?
    @Published var filteredPreviewImage: UIImage?
    @Published var selectedFilter = PhotoFilter.fallback
    @Published var isFrameStable = false
    @Published var statusText = "等待相机权限"
    @Published var photoStatusText: String?
    @Published var zoomFactor: CGFloat = 1
    @Published var minZoomFactor: CGFloat = 1
    @Published var maxZoomFactor: CGFloat = 1
    @Published var cameraPosition: AVCaptureDevice.Position = .back

    private let sessionQueue = DispatchQueue(label: "camera.session.queue")
    private let videoOutputQueue = DispatchQueue(label: "camera.video.output.queue")
    private let videoOutput = AVCaptureVideoDataOutput()
    private let photoOutput = AVCapturePhotoOutput()
    private let visionAnalyzer = VisionAnalyzer()
    private let compositionEngine = CompositionEngine()
    private let filterEngine = FilterEngine()
    private let filterLock = NSLock()
    private let captureAspectRatioLock = NSLock()
    private let ciContext = CIContext()
    private var videoDevice: AVCaptureDevice?
    private var videoInput: AVCaptureDeviceInput?
    private var activeFilter = PhotoFilter.fallback
    private var pendingCaptureAspectRatio = ShootingAspectRatio.full
    private var lastAnalysisTime = Date.distantPast
    private var lastImageUpdateTime = Date.distantPast
    private var lastPreviewUpdateTime = Date.distantPast
    private var lastCompositionUpdateTime = Date.distantPast
    private var lastPublishedResult: CompositionResult?
    private var lastSubjectCenter: CGPoint?
    private var stableFrameCount = 0
    private var isSessionConfigured = false
    private var analysisFrameIndex = 0

    @MainActor
    func requestAccessAndStart() async {
        authorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)

        if authorizationStatus == .notDetermined {
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            authorizationStatus = granted ? .authorized : .denied
        }

        guard authorizationStatus == .authorized else {
            statusText = "请在系统设置中允许相机权限"
            return
        }

        statusText = "正在启动相机"
        sessionQueue.async { [weak self] in
            self?.configureAndStartSession()
        }
    }

    func stop() {
        sessionQueue.async { [weak self] in
            self?.session.stopRunning()
        }
    }

    func capturePhoto(aspectRatio: ShootingAspectRatio) {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            guard self.session.isRunning else {
                DispatchQueue.main.async { self.photoStatusText = "相机还没准备好。" }
                return
            }
            self.setPendingCaptureAspectRatio(aspectRatio)
            DispatchQueue.main.async { self.photoStatusText = "正在处理照片..." }
            let settings = AVCapturePhotoSettings()
            self.photoOutput.capturePhoto(with: settings, delegate: self)
        }
    }

    func setSelectedFilter(_ filter: PhotoFilter) {
        filterLock.lock()
        activeFilter = filter
        filterLock.unlock()

        DispatchQueue.main.async {
            self.selectedFilter = filter
            self.filteredPreviewImage = nil
        }
    }

    func setZoomFactor(_ factor: CGFloat) {
        sessionQueue.async { [weak self] in
            guard let self, let device = self.videoDevice else { return }
            let minZoom = device.minAvailableVideoZoomFactor
            let maxZoom = min(device.maxAvailableVideoZoomFactor, 8)
            let clamped = min(max(factor, minZoom), maxZoom)

            do {
                try device.lockForConfiguration()
                if device.isRampingVideoZoom {
                    device.cancelVideoZoomRamp()
                }
                device.ramp(toVideoZoomFactor: clamped, withRate: 7)
                device.unlockForConfiguration()

                DispatchQueue.main.async {
                    self.zoomFactor = clamped
                }
            } catch {
                DispatchQueue.main.async {
                    self.photoStatusText = "无法切换变焦：\(error.localizedDescription)"
                }
            }
        }
    }

    func switchCamera() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            let nextPosition: AVCaptureDevice.Position = self.cameraPosition == .back ? .front : .back
            self.session.beginConfiguration()
            let didSwitch = self.configureVideoInput(position: nextPosition)
            self.applyVideoConnectionSettings(position: didSwitch ? nextPosition : self.cameraPosition)
            self.session.commitConfiguration()

            DispatchQueue.main.async {
                if didSwitch {
                    self.cameraPosition = nextPosition
                    self.photoStatusText = nextPosition == .front ? "已切换前置相机。" : "已切换后置相机。"
                } else {
                    self.photoStatusText = "当前设备无法切换相机。"
                }
            }
        }
    }

    func focusAndExpose(at devicePoint: CGPoint) {
        sessionQueue.async { [weak self] in
            guard let self, let device = self.videoDevice else { return }
            let point = CGPoint(
                x: min(max(devicePoint.x, 0), 1),
                y: min(max(devicePoint.y, 0), 1)
            )

            do {
                try device.lockForConfiguration()
                if device.isFocusPointOfInterestSupported {
                    device.focusPointOfInterest = point
                    if device.isFocusModeSupported(.autoFocus) {
                        device.focusMode = .autoFocus
                    }
                }
                if device.isExposurePointOfInterestSupported {
                    device.exposurePointOfInterest = point
                    if device.isExposureModeSupported(.continuousAutoExposure) {
                        device.exposureMode = .continuousAutoExposure
                    }
                }
                device.unlockForConfiguration()

                DispatchQueue.main.async {
                    self.photoStatusText = "已锁定对焦和曝光。"
                }
            } catch {
                DispatchQueue.main.async {
                    self.photoStatusText = "对焦失败：\(error.localizedDescription)"
                }
            }
        }
    }

    private func configureAndStartSession() {
        if session.isRunning { return }

        if !isSessionConfigured {
            session.beginConfiguration()
            session.sessionPreset = .photo

            defer {
                session.commitConfiguration()
            }

            guard configureVideoInput(position: .back) else {
                DispatchQueue.main.async { self.statusText = "无法打开后置相机" }
                return
            }

            videoOutput.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
            ]
            videoOutput.alwaysDiscardsLateVideoFrames = true
            videoOutput.setSampleBufferDelegate(self, queue: videoOutputQueue)

            if session.canAddOutput(videoOutput) {
                session.addOutput(videoOutput)
            }

            if session.canAddOutput(photoOutput) {
                session.addOutput(photoOutput)
            }

            applyVideoConnectionSettings(position: .back)
            isSessionConfigured = true
        }

        session.startRunning()

        DispatchQueue.main.async { self.statusText = "实时构图分析中" }
    }

    private func configureVideoInput(position: AVCaptureDevice.Position) -> Bool {
        guard let device = preferredCamera(position: position),
              let input = try? AVCaptureDeviceInput(device: device) else {
            return false
        }

        let previousInput = videoInput
        if let previousInput {
            session.removeInput(previousInput)
        }

        guard session.canAddInput(input) else {
            if let previousInput, session.canAddInput(previousInput) {
                session.addInput(previousInput)
            }
            return false
        }

        session.addInput(input)
        videoDevice = device
        videoInput = input
        publishZoomBounds(for: device)
        return true
    }

    private func preferredCamera(position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        if position == .front {
            return AVCaptureDevice.default(.builtInTrueDepthCamera, for: .video, position: .front) ??
            AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
        }

        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [
                .builtInTripleCamera,
                .builtInDualWideCamera,
                .builtInDualCamera,
                .builtInWideAngleCamera
            ],
            mediaType: .video,
            position: position
        )
        return discovery.devices.first ?? AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
    }

    private func applyVideoConnectionSettings(position: AVCaptureDevice.Position) {
        [videoOutput.connection(with: .video), photoOutput.connection(with: .video)].forEach { connection in
            connection?.videoOrientation = .portrait
            if connection?.isVideoMirroringSupported == true {
                connection?.isVideoMirrored = position == .front
            }
        }
    }

    private func publishZoomBounds(for device: AVCaptureDevice) {
        let minZoom = device.minAvailableVideoZoomFactor
        let maxZoom = min(device.maxAvailableVideoZoomFactor, 8)
        DispatchQueue.main.async {
            self.minZoomFactor = minZoom
            self.maxZoomFactor = maxZoom
            self.zoomFactor = min(max(device.videoZoomFactor, minZoom), maxZoom)
        }
    }

    private func process(sampleBuffer: CMSampleBuffer) {
        let now = Date()
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        guard now.timeIntervalSince(lastAnalysisTime) >= 0.08 else { return }

        lastAnalysisTime = now

        let frameSize = CGSize(
            width: CVPixelBufferGetWidth(pixelBuffer),
            height: CVPixelBufferGetHeight(pixelBuffer)
        )

        analysisFrameIndex += 1
        let includeSaliency = analysisFrameIndex % 6 == 0
        let observations = visionAnalyzer.analyze(
            pixelBuffer: pixelBuffer,
            frameSize: frameSize,
            includeSaliency: includeSaliency
        )
        let result = compositionEngine.evaluate(observations: observations)
        let stable = updateStability(subjectCenter: result.primarySubject?.rect.center)
        let shouldUpdateImage = now.timeIntervalSince(lastImageUpdateTime) >= 1
        let shouldUpdatePreview = now.timeIntervalSince(lastPreviewUpdateTime) >= 0.12
        let filter = currentFilter()
        let originalImage = shouldUpdateImage ? makeUIImage(from: pixelBuffer) : nil
        if shouldUpdateImage { lastImageUpdateTime = now }
        let shouldUpdateFilteredPreview = shouldUpdatePreview && filter.id != PhotoFilter.fallback.id
        let filteredPreviewImage = shouldUpdateFilteredPreview ? makeFilteredPreviewImage(from: pixelBuffer, filter: filter) : nil
        if shouldUpdateFilteredPreview { lastPreviewUpdateTime = now }
        let displayedResult = compositionResultToPublish(result, now: now)

        DispatchQueue.main.async {
            if let displayedResult {
                self.compositionResult = displayedResult
            }
            if let originalImage {
                self.latestImage = originalImage
            }
            if let filteredPreviewImage {
                self.filteredPreviewImage = filteredPreviewImage
            }
            self.isFrameStable = stable
        }
    }

    private func updateStability(subjectCenter: CGPoint?) -> Bool {
        guard let subjectCenter else {
            stableFrameCount = 0
            lastSubjectCenter = nil
            return false
        }

        if let lastSubjectCenter {
            let dx = subjectCenter.x - lastSubjectCenter.x
            let dy = subjectCenter.y - lastSubjectCenter.y
            let distance = sqrt(dx * dx + dy * dy)
            stableFrameCount = distance < 0.025 ? stableFrameCount + 1 : 0
        } else {
            stableFrameCount = 0
        }

        lastSubjectCenter = subjectCenter
        return stableFrameCount >= 8
    }

    private func compositionResultToPublish(_ result: CompositionResult, now: Date) -> CompositionResult? {
        let shouldPublish = now.timeIntervalSince(lastCompositionUpdateTime) >= 0.35

        guard shouldPublish || lastPublishedResult == nil else { return nil }

        lastCompositionUpdateTime = now
        lastPublishedResult = result
        return result
    }

    private func makeUIImage(from pixelBuffer: CVPixelBuffer) -> UIImage? {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer).oriented(.right)
        guard let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }

    private func makeFilteredPreviewImage(from pixelBuffer: CVPixelBuffer, filter: PhotoFilter) -> UIImage? {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer).oriented(.right)
        let filteredImage = filterEngine.apply(filter: filter, to: ciImage)
        return filterEngine.makeUIImage(from: filteredImage)
    }

    private func currentFilter() -> PhotoFilter {
        filterLock.lock()
        let filter = activeFilter
        filterLock.unlock()
        return filter
    }

    private func setPendingCaptureAspectRatio(_ aspectRatio: ShootingAspectRatio) {
        captureAspectRatioLock.lock()
        pendingCaptureAspectRatio = aspectRatio
        captureAspectRatioLock.unlock()
    }

    private func currentCaptureAspectRatio() -> ShootingAspectRatio {
        captureAspectRatioLock.lock()
        let aspectRatio = pendingCaptureAspectRatio
        captureAspectRatioLock.unlock()
        return aspectRatio
    }
}

extension CameraSessionController: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        self.process(sampleBuffer: sampleBuffer)
    }
}

extension CameraSessionController: AVCapturePhotoCaptureDelegate {
    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        if let error {
            DispatchQueue.main.async {
                self.photoStatusText = "拍照失败：\(error.localizedDescription)"
            }
            return
        }

        guard let data = photo.fileDataRepresentation(), let image = UIImage(data: data) else {
            DispatchQueue.main.async {
                self.photoStatusText = "拍照失败：无法读取照片。"
            }
            return
        }

        let filteredImage = filterEngine.apply(filter: currentFilter(), to: image) ?? image
        let outputImage = crop(filteredImage, to: currentCaptureAspectRatio()) ?? filteredImage
        saveToPhotoLibrary(outputImage)
        DispatchQueue.main.async {
            self.latestImage = outputImage
        }
    }

    private func crop(_ image: UIImage, to aspectRatio: ShootingAspectRatio) -> UIImage? {
        guard let targetRatio = aspectRatio.numericRatio else { return image }
        let imageSize = image.size
        guard imageSize.width > 0, imageSize.height > 0 else { return image }

        let currentRatio = imageSize.width / imageSize.height
        let cropSize: CGSize
        if currentRatio > targetRatio {
            cropSize = CGSize(width: imageSize.height * targetRatio, height: imageSize.height)
        } else {
            cropSize = CGSize(width: imageSize.width, height: imageSize.width / targetRatio)
        }

        let cropOrigin = CGPoint(
            x: (imageSize.width - cropSize.width) / 2,
            y: (imageSize.height - cropSize.height) / 2
        )

        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale
        format.opaque = false

        return UIGraphicsImageRenderer(size: cropSize, format: format).image { _ in
            image.draw(
                at: CGPoint(x: -cropOrigin.x, y: -cropOrigin.y)
            )
        }
    }

    private func saveToPhotoLibrary(_ image: UIImage) {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { [weak self] status in
            guard status == .authorized || status == .limited else {
                DispatchQueue.main.async { self?.photoStatusText = "没有相册保存权限。" }
                return
            }

            PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAsset(from: image)
            } completionHandler: { success, error in
                DispatchQueue.main.async {
                    if success {
                        self?.photoStatusText = "照片已保存到相册。"
                    } else {
                        self?.photoStatusText = "保存失败：\(error?.localizedDescription ?? "未知错误")"
                    }
                }
            }
        }
    }
}
