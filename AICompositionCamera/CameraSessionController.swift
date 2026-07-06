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
    @Published var previewImage: UIImage?
    @Published var selectedFilter = PhotoFilter.fallback
    @Published var isFrameStable = false
    @Published var statusText = "等待相机权限"
    @Published var photoStatusText: String?

    private let sessionQueue = DispatchQueue(label: "camera.session.queue")
    private let videoOutputQueue = DispatchQueue(label: "camera.video.output.queue")
    private let videoOutput = AVCaptureVideoDataOutput()
    private let photoOutput = AVCapturePhotoOutput()
    private let visionAnalyzer = VisionAnalyzer()
    private let compositionEngine = CompositionEngine()
    private let filterEngine = FilterEngine()
    private let filterLock = NSLock()
    private let ciContext = CIContext()
    private var activeFilter = PhotoFilter.fallback
    private var lastAnalysisTime = Date.distantPast
    private var lastImageUpdateTime = Date.distantPast
    private var lastPreviewImageUpdateTime = Date.distantPast
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

    func capturePhoto() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            guard self.session.isRunning else {
                DispatchQueue.main.async { self.photoStatusText = "相机还没准备好。" }
                return
            }
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

            guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
                  let input = try? AVCaptureDeviceInput(device: device),
                  session.canAddInput(input) else {
                DispatchQueue.main.async { self.statusText = "无法打开后置相机" }
                return
            }

            session.addInput(input)

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

            videoOutput.connection(with: .video)?.videoOrientation = .portrait
            photoOutput.connection(with: .video)?.videoOrientation = .portrait
            isSessionConfigured = true
        }

        session.startRunning()

        DispatchQueue.main.async { self.statusText = "实时构图分析中" }
    }

    private func process(sampleBuffer: CMSampleBuffer) {
        let now = Date()
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let shouldAnalyze = now.timeIntervalSince(lastAnalysisTime) >= 0.08
        let shouldUpdatePreview = now.timeIntervalSince(lastPreviewImageUpdateTime) >= 1.0 / 24.0
        guard shouldAnalyze || shouldUpdatePreview else { return }

        let filter = currentFilter()
        let previewImage = shouldUpdatePreview ? makeFilteredUIImage(from: pixelBuffer, filter: filter) : nil
        if shouldUpdatePreview { lastPreviewImageUpdateTime = now }

        guard shouldAnalyze else {
            if let previewImage {
                DispatchQueue.main.async {
                    self.previewImage = previewImage
                }
            }
            return
        }

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
        let originalImage = shouldUpdateImage ? makeUIImage(from: pixelBuffer) : nil
        if shouldUpdateImage { lastImageUpdateTime = now }

        DispatchQueue.main.async {
            self.compositionResult = result
            if let originalImage {
                self.latestImage = originalImage
            }
            self.previewImage = previewImage
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

    private func makeUIImage(from pixelBuffer: CVPixelBuffer) -> UIImage? {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer).oriented(.right)
        guard let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }

    private func makeFilteredUIImage(from pixelBuffer: CVPixelBuffer, filter: PhotoFilter) -> UIImage? {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer).oriented(.right)
        return filterEngine.makeUIImage(from: filterEngine.apply(filter: filter, to: ciImage))
    }

    private func currentFilter() -> PhotoFilter {
        filterLock.lock()
        let filter = activeFilter
        filterLock.unlock()
        return filter
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
        guard error == nil, let data = photo.fileDataRepresentation(), let image = UIImage(data: data) else { return }
        let outputImage = filterEngine.apply(filter: currentFilter(), to: image) ?? image
        saveToPhotoLibrary(outputImage)
        DispatchQueue.main.async {
            self.latestImage = outputImage
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
