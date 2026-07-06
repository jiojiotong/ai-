import SwiftUI

struct OverlayView: View {
    let result: CompositionResult?
    let intensity: OverlayIntensity

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if intensity != .minimal {
                    thirdsGrid(in: geometry.size)
                }

                ForEach(Array((result?.overlays ?? []).enumerated()), id: \.offset) { _, overlay in
                    draw(overlay, in: geometry.size)
                }
            }
        }
        .allowsHitTesting(false)
    }

    private func thirdsGrid(in size: CGSize) -> some View {
        Path { path in
            let x1 = size.width / 3
            let x2 = size.width * 2 / 3
            let y1 = size.height / 3
            let y2 = size.height * 2 / 3

            path.move(to: CGPoint(x: x1, y: 0))
            path.addLine(to: CGPoint(x: x1, y: size.height))
            path.move(to: CGPoint(x: x2, y: 0))
            path.addLine(to: CGPoint(x: x2, y: size.height))
            path.move(to: CGPoint(x: 0, y: y1))
            path.addLine(to: CGPoint(x: size.width, y: y1))
            path.move(to: CGPoint(x: 0, y: y2))
            path.addLine(to: CGPoint(x: size.width, y: y2))
        }
        .stroke(.white.opacity(intensity == .detailed ? 0.35 : 0.22), lineWidth: 1)
    }

    @ViewBuilder
    private func draw(_ overlay: CompositionOverlay, in size: CGSize) -> some View {
        switch overlay {
        case .thirdsGrid:
            EmptyView()
        case .subjectBox(let rect):
            box(rect, color: .cyan, in: size)
        case .faceBox(let rect):
            box(rect, color: .green, in: size)
        case .horizon(let y):
            Path { path in
                path.move(to: CGPoint(x: 0, y: y * size.height))
                path.addLine(to: CGPoint(x: size.width, y: y * size.height))
            }
            .stroke(.yellow.opacity(0.8), style: StrokeStyle(lineWidth: 2, dash: [8, 8]))
        case .arrow(let direction, let origin):
            arrow(direction: direction, origin: origin, in: size)
        }
    }

    private func box(_ rect: CGRect, color: Color, in size: CGSize) -> some View {
        RoundedRectangle(cornerRadius: 10)
            .stroke(color.opacity(0.85), lineWidth: 2)
            .frame(width: rect.width * size.width, height: rect.height * size.height)
            .position(x: rect.midX * size.width, y: rect.midY * size.height)
    }

    private func arrow(direction: ArrowDirection, origin: CGPoint, in size: CGSize) -> some View {
        let systemName: String = {
            switch direction {
            case .left: return "arrow.left"
            case .right: return "arrow.right"
            case .up: return "arrow.up"
            case .down: return "arrow.down"
            }
        }()

        return Image(systemName: systemName)
            .font(.system(size: 34, weight: .bold))
            .foregroundStyle(.yellow)
            .shadow(radius: 4)
            .position(x: origin.x * size.width, y: origin.y * size.height)
    }
}
