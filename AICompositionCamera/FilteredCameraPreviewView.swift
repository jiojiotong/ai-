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
                        let normalizedX = min(max(layerPoint.x / viewSize.width, 0), 1)
                        let devicePoint = CGPoint(
                            x: mirrored ? 1 - normalizedX : normalizedX,
                            y: min(max(layerPoint.y / viewSize.height, 0), 1)
                        )
                        onTapFocus(devicePoint, layerPoint)
                    }
            )
        }
    }
}
