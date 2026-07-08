import SwiftUI
import UIKit

struct FilteredCameraPreviewView: View {
    let image: UIImage?
    var mirrored = false
    var onTapFocus: (CGPoint, CGPoint) -> Void = { _, _ in }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.black

                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .scaleEffect(x: mirrored ? -1 : 1, y: 1)
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .clipped()
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onEnded { value in
                        let viewSize = proxy.size
                        guard viewSize.width > 0, viewSize.height > 0 else { return }
                        let layerPoint = value.location
                        let imageAspectRatio = image.map { $0.size.width / max($0.size.height, 1) } ?? (9.0 / 16.0)
                        let imageRect = aspectFillRect(imageAspectRatio: imageAspectRatio, in: viewSize)
                        let normalizedX = min(max((layerPoint.x - imageRect.minX) / imageRect.width, 0), 1)
                        let normalizedY = min(max((layerPoint.y - imageRect.minY) / imageRect.height, 0), 1)
                        let devicePoint = CGPoint(
                            x: mirrored ? 1 - normalizedX : normalizedX,
                            y: normalizedY
                        )
                        onTapFocus(devicePoint, layerPoint)
                    }
            )
        }
    }

    private func aspectFillRect(imageAspectRatio: CGFloat, in size: CGSize) -> CGRect {
        let viewAspectRatio = size.width / max(size.height, 1)

        if imageAspectRatio > viewAspectRatio {
            let height = size.height
            let width = height * imageAspectRatio
            return CGRect(x: (size.width - width) / 2, y: 0, width: width, height: height)
        } else {
            let width = size.width
            let height = width / max(imageAspectRatio, 0.01)
            return CGRect(x: 0, y: (size.height - height) / 2, width: width, height: height)
        }
    }
}
