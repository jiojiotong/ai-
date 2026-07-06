import AVFoundation
import Combine
import CoreImage
import UIKit

final class CameraSessionController: NSObject, ObservableObject {
    let session = AVCaptureSession()

    @Published var authorizationStatus: AVAuthorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
    @Published var compositionResult: CompositionResult?
    @Published var latestImage: UIImage?
    @Published var isFrameStable = false
    @Published var statusText = "等待相机权限"

    private let sessionQueue = DispatchQueue(label: "camera.session.queue")
    private let videoOutput = AVCaptureVideoDataOutput()
    private let photoOutput = AVCapturePhotoOutput()
    private let visionAnalyzer = VisionAnalyzer()
    private let compositionEngine = CompositionEngine()
    private let ciContext = CIContext()
    private var lastAnalysisTime = Date.distantPast
    private var lastSubjectCenter: CGPoint?
    private var stableFrameCount = 0

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
            let settings = AVCapturePhotoSettings()
            self.photoOutput.capturePhoto(with: settings, delegate: self)
        }
    }

    private func configureAndStartSession() {
        guard !session.isRunning else { return }

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
        videoOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "camera.video.output.queue"))

        if session.canAddOutput(videoOutput) {
            session.addOutput(videoOutput)
        }

        if session.canAddOutput(photoOutput) {
            session.addOutput(photoOutput)
        }

        videoOutput.connection(with: .video)?.videoOrientation = .portrait
        photoOutput.connection(with: .video)?.videoOrientation = .portrait

        session.startRunning()

        DispatchQueue.main.async { self.statusText = "实时构图分析中" }
    }

    private func process(sampleBuffer: CMSampleBuffer) {
        let now = Date()
        guard now.timeIntervalSince(lastAnalysisTime) >= 0.08 else { return }
        lastAnalysisTime = now

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let frameSize = CGSize(
            width: CVPixelBufferGetWidth(pixelBuffer),
            height: CVPixelBufferGetHeight(pixelBuffer)
        )

        let observations = visionAnalyzer.analyze(pixelBuffer: pixelBuffer, frameSize: frameSize)
        let result = compositionEngine.evaluate(observations: observations)
        let image = makeUIImage(from: pixelBuffer)
        let stable = updateStability(subjectCenter: result.primarySubject?.rect.center)

        DispatchQueue.main.async {
            self.compositionResult = result
            self.latestImage = image
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
        DispatchQueue.main.async {
            self.latestImage = image
        }
    }
}
