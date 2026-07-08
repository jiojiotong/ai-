import Foundation
import SwiftUI

struct CaptureGuidanceOverlay: View {
    let guidance: CaptureGuidance?
    let imageAspectRatio: CGFloat
    let currentZoomFactor: CGFloat

    var body: some View {
        GeometryReader { geometry in
            let displayRect = aspectFillRect(imageAspectRatio: imageAspectRatio, in: geometry.size)

            ZStack {
                if let targetRect = guidance?.targetRect {
                    targetBox(targetRect, in: displayRect)
                }

                if let guidance {
                    directionCue(guidance, in: displayRect)

                    if let zoomFactor = guidance.zoomFactor {
                        zoomCue(zoomFactor, in: displayRect)
                    }
                }
            }
        }
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func targetBox(_ rect: CGRect, in displayRect: CGRect) -> some View {
        let mapped = map(rect, into: displayRect)
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .stroke(.white.opacity(0.78), style: StrokeStyle(lineWidth: 2, dash: [7, 7]))
            .frame(width: mapped.width, height: mapped.height)
            .position(x: mapped.midX, y: mapped.midY)
            .shadow(color: .black.opacity(0.55), radius: 5, x: 0, y: 2)
    }

    @ViewBuilder
    private func directionCue(_ guidance: CaptureGuidance, in displayRect: CGRect) -> some View {
        if let direction = guidance.direction {
            if direction == .closer || direction == .farther {
                EmptyView()
            } else {
                let point = cuePosition(for: direction, in: displayRect)
                VStack(spacing: 8) {
                    Image(systemName: direction.systemImage)
                        .font(.system(size: direction == .hold ? 30 : 46, weight: .heavy))
                        .foregroundStyle(direction == .hold ? .black : .white)
                        .frame(width: 76, height: 76)
                        .background(direction == .hold ? Color.green.opacity(0.92) : Color.black.opacity(0.44), in: Circle())
                        .overlay {
                            Circle()
                                .stroke(.white.opacity(direction == .hold ? 0.0 : 0.52), lineWidth: 1.5)
                        }
                        .shadow(color: .black.opacity(0.42), radius: 10, x: 0, y: 5)

                    Text(guidance.message.isEmpty ? direction.title : guidance.message)
                        .font(.caption.weight(.heavy))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(.black.opacity(0.42), in: Capsule())
                }
                .frame(width: 160)
                .position(point)
            }
        }
    }

    @ViewBuilder
    private func zoomCue(_ zoomFactor: CGFloat, in displayRect: CGRect) -> some View {
        let isCurrent = abs(currentZoomFactor - zoomFactor) < 0.08
        HStack(spacing: 7) {
            Image(systemName: isCurrent ? "checkmark" : "scope")
                .font(.system(size: 13, weight: .heavy))
            Text("\(zoomLabel(zoomFactor))x")
                .font(.headline.weight(.heavy))
        }
        .foregroundStyle(isCurrent ? .black : .white)
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(isCurrent ? Color.green.opacity(0.92) : Color.black.opacity(0.48), in: Capsule())
        .overlay {
            Capsule()
                .stroke(.white.opacity(isCurrent ? 0 : 0.38), lineWidth: 1)
        }
        .position(x: displayRect.midX, y: displayRect.maxY - 86)
    }

    private func cuePosition(for direction: CameraMoveDirection, in rect: CGRect) -> CGPoint {
        switch direction {
        case .left:
            return CGPoint(x: rect.minX + rect.width * 0.25, y: rect.midY)
        case .right:
            return CGPoint(x: rect.maxX - rect.width * 0.25, y: rect.midY)
        case .up:
            return CGPoint(x: rect.midX, y: rect.minY + rect.height * 0.24)
        case .down:
            return CGPoint(x: rect.midX, y: rect.maxY - rect.height * 0.28)
        case .closer, .farther, .hold:
            return CGPoint(x: rect.midX, y: rect.midY)
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

    private func map(_ rect: CGRect, into displayRect: CGRect) -> CGRect {
        CGRect(
            x: displayRect.minX + rect.minX * displayRect.width,
            y: displayRect.minY + rect.minY * displayRect.height,
            width: rect.width * displayRect.width,
            height: rect.height * displayRect.height
        )
    }

    private func zoomLabel(_ value: CGFloat) -> String {
        let rounded = (value * 10).rounded() / 10
        if rounded.rounded() == rounded {
            return String(Int(rounded))
        }
        return String(format: "%.1f", Double(rounded))
    }
}
