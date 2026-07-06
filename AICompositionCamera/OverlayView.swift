import SwiftUI

struct OverlayView: View {
    let result: CompositionResult?
    let intensity: OverlayIntensity

    var body: some View {
        GeometryReader { geometry in
            let displayRect = aspectFillRect(
                imageAspectRatio: result?.imageAspectRatio ?? 9.0 / 16.0,
                in: geometry.size
            )

            ZStack {
                if intensity != .minimal {
                    thirdsGrid(in: displayRect)
                }

                ForEach(Array((result?.overlays ?? []).enumerated()), id: \.offset) { _, overlay in
                    draw(overlay, in: displayRect)
                }
            }
        }
        .allowsHitTesting(false)
    }

    private func thirdsGrid(in rect: CGRect) -> some View {
        Path { path in
            let x1 = rect.minX + rect.width / 3
            let x2 = rect.minX + rect.width * 2 / 3
            let y1 = rect.minY + rect.height / 3
            let y2 = rect.minY + rect.height * 2 / 3

            path.move(to: CGPoint(x: x1, y: rect.minY))
            path.addLine(to: CGPoint(x: x1, y: rect.maxY))
            path.move(to: CGPoint(x: x2, y: rect.minY))
            path.addLine(to: CGPoint(x: x2, y: rect.maxY))
            path.move(to: CGPoint(x: rect.minX, y: y1))
            path.addLine(to: CGPoint(x: rect.maxX, y: y1))
            path.move(to: CGPoint(x: rect.minX, y: y2))
            path.addLine(to: CGPoint(x: rect.maxX, y: y2))
        }
        .stroke(.white.opacity(intensity == .detailed ? 0.35 : 0.22), lineWidth: 1)
    }

    @ViewBuilder
    private func draw(_ overlay: CompositionOverlay, in displayRect: CGRect) -> some View {
        switch overlay {
        case .thirdsGrid:
            EmptyView()
        case .subjectBox(let rect):
            box(rect, color: .cyan, in: displayRect)
        case .faceBox(let rect):
            box(rect, color: .green, in: displayRect)
        case .horizon(let y):
            Path { path in
                let mappedY = displayRect.minY + y * displayRect.height
                path.move(to: CGPoint(x: displayRect.minX, y: mappedY))
                path.addLine(to: CGPoint(x: displayRect.maxX, y: mappedY))
            }
            .stroke(.yellow.opacity(0.8), style: StrokeStyle(lineWidth: 2, dash: [8, 8]))
        case .arrow(let direction, let origin):
            arrow(direction: direction, origin: origin, in: displayRect)
        }
    }

    private func box(_ rect: CGRect, color: Color, in displayRect: CGRect) -> some View {
        let mapped = map(rect, into: displayRect)
        RoundedRectangle(cornerRadius: 10)
            .stroke(color.opacity(0.85), lineWidth: 2)
            .frame(width: mapped.width, height: mapped.height)
            .position(x: mapped.midX, y: mapped.midY)
    }

    private func arrow(direction: ArrowDirection, origin: CGPoint, in displayRect: CGRect) -> some View {
        let systemName: String = {
            switch direction {
            case .left: return "arrow.left"
            case .right: return "arrow.right"
            case .up: return "arrow.up"
            case .down: return "arrow.down"
            }
        }()

        let point = map(origin, into: displayRect)
        return Image(systemName: systemName)
            .font(.system(size: 34, weight: .bold))
            .foregroundStyle(.yellow)
            .shadow(radius: 4)
            .position(x: point.x, y: point.y)
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

    private func map(_ rect: CGRect, into displayRect: CGRect) -> CGRect {
        CGRect(
            x: displayRect.minX + rect.minX * displayRect.width,
            y: displayRect.minY + rect.minY * displayRect.height,
            width: rect.width * displayRect.width,
            height: rect.height * displayRect.height
        )
    }

    private func map(_ point: CGPoint, into displayRect: CGRect) -> CGPoint {
        CGPoint(
            x: displayRect.minX + point.x * displayRect.width,
            y: displayRect.minY + point.y * displayRect.height
        )
    }
}
