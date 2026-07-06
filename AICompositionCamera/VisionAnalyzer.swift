import CoreGraphics
import Vision

final class VisionAnalyzer {
    func analyze(pixelBuffer: CVPixelBuffer, frameSize: CGSize, includeSaliency: Bool) -> VisionObservations {
        let faceRequest = VNDetectFaceRectanglesRequest()
        let humanRequest = VNDetectHumanRectanglesRequest()
        let saliencyRequest = includeSaliency ? VNGenerateAttentionBasedSaliencyImageRequest() : nil

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .right, options: [:])
        do {
            var requests: [VNRequest] = [faceRequest, humanRequest]
            if let saliencyRequest { requests.append(saliencyRequest) }
            try handler.perform(requests)
        } catch {
            return VisionObservations(faces: [], humans: [], salientObjects: [], frameSize: frameSize)
        }

        let faces = (faceRequest.results ?? []).map { convertVisionRect($0.boundingBox) }
        let humans = (humanRequest.results ?? []).map { convertVisionRect($0.boundingBox) }
        let objects = saliencyRequest?.results?.first?.salientObjects?.map { convertVisionRect($0.boundingBox) } ?? []

        return VisionObservations(
            faces: faces,
            humans: humans,
            salientObjects: objects,
            frameSize: frameSize
        )
    }

    private func convertVisionRect(_ rect: CGRect) -> CGRect {
        CGRect(x: rect.minX, y: 1 - rect.maxY, width: rect.width, height: rect.height)
    }
}
