import AVFoundation
import SwiftUI
import UIKit

struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession
    var mirrored = false
    var onTapFocus: (CGPoint, CGPoint) -> Void = { _, _ in }

    func makeUIView(context: Context) -> PreviewUIView {
        let view = PreviewUIView()
        view.videoPreviewLayer.session = session
        view.videoPreviewLayer.videoGravity = .resizeAspectFill
        view.mirrored = mirrored
        view.onTapFocus = onTapFocus
        view.updateOrientation()
        return view
    }

    func updateUIView(_ uiView: PreviewUIView, context: Context) {
        uiView.videoPreviewLayer.session = session
        uiView.mirrored = mirrored
        uiView.onTapFocus = onTapFocus
        uiView.updateOrientation()
    }
}

final class PreviewUIView: UIView {
    var mirrored = false
    var onTapFocus: (CGPoint, CGPoint) -> Void = { _, _ in }

    override class var layerClass: AnyClass {
        AVCaptureVideoPreviewLayer.self
    }

    var videoPreviewLayer: AVCaptureVideoPreviewLayer {
        layer as! AVCaptureVideoPreviewLayer
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        addTapGesture()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        addTapGesture()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        updateOrientation()
    }

    func updateOrientation() {
        videoPreviewLayer.frame = bounds
        videoPreviewLayer.connection?.videoOrientation = .portrait
        if videoPreviewLayer.connection?.isVideoMirroringSupported == true {
            videoPreviewLayer.connection?.isVideoMirrored = mirrored
        }
    }

    private func addTapGesture() {
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        addGestureRecognizer(tap)
    }

    @objc private func handleTap(_ recognizer: UITapGestureRecognizer) {
        let layerPoint = recognizer.location(in: self)
        let devicePoint = videoPreviewLayer.captureDevicePointConverted(fromLayerPoint: layerPoint)
        onTapFocus(devicePoint, layerPoint)
    }
}
