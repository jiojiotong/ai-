import CoreGraphics

struct VisionObservations {
    var faces: [CGRect]
    var humans: [CGRect]
    var salientObjects: [CGRect]
    var frameSize: CGSize

    var displayAspectRatio: CGFloat {
        let shortSide = min(frameSize.width, frameSize.height)
        let longSide = max(frameSize.width, frameSize.height)
        guard shortSide > 0, longSide > 0 else { return 9.0 / 16.0 }
        return shortSide / longSide
    }
}

struct CompositionResult {
    var rules: [CompositionRuleResult]
    var primarySubject: CompositionSubject?
    var imageAspectRatio: CGFloat

    var topSuggestion: String? {
        rules
            .filter { !$0.suggestion.isEmpty }
            .sorted { lhs, rhs in
                if lhs.priority == rhs.priority { return lhs.confidence > rhs.confidence }
                return lhs.priority > rhs.priority
            }
            .first?.suggestion
    }

    var overlays: [CompositionOverlay] {
        rules.compactMap(\.overlay)
    }

    var hermesContext: String {
        let topRules = rules
            .sorted { $0.priority > $1.priority }
            .prefix(4)
            .map { "\($0.category.rawValue): \($0.suggestion) score=\(Int($0.score * 100)) confidence=\(Int($0.confidence * 100))" }
            .joined(separator: "; ")
        return topRules.isEmpty ? "No strong local composition issue detected." : topRules
    }

    var sceneSignature: String {
        guard let subject = primarySubject else { return "no-subject" }
        let x = Int((subject.rect.midX * 10).rounded())
        let y = Int((subject.rect.midY * 10).rounded())
        let w = Int((subject.rect.width * 10).rounded())
        let h = Int((subject.rect.height * 10).rounded())
        return "\(subject.kind.rawValue)-\(x)-\(y)-\(w)-\(h)-\(topSuggestion ?? "")"
    }

    var liveGuidance: CaptureGuidance {
        guard let subject = primarySubject else {
            return CaptureGuidance(
                direction: nil,
                zoomFactor: nil,
                message: "把主体放进取景框",
                targetRect: nil,
                source: .local,
                priority: 40
            )
        }

        let rect = subject.rect
        let center = rect.center

        if rect.minX < 0.04 || center.x < 0.30 {
            return CaptureGuidance(
                direction: .left,
                zoomFactor: nil,
                message: "相机左移",
                targetRect: targetRect(for: rect, center: CGPoint(x: 0.5, y: center.y)),
                source: .local,
                priority: 90
            )
        }

        if rect.maxX > 0.96 || center.x > 0.70 {
            return CaptureGuidance(
                direction: .right,
                zoomFactor: nil,
                message: "相机右移",
                targetRect: targetRect(for: rect, center: CGPoint(x: 0.5, y: center.y)),
                source: .local,
                priority: 90
            )
        }

        if rect.minY < 0.04 || center.y < 0.26 {
            return CaptureGuidance(
                direction: .up,
                zoomFactor: nil,
                message: "相机上移",
                targetRect: targetRect(for: rect, center: CGPoint(x: center.x, y: 0.5)),
                source: .local,
                priority: 88
            )
        }

        if rect.maxY > 0.96 || center.y > 0.74 {
            return CaptureGuidance(
                direction: .down,
                zoomFactor: nil,
                message: "相机下移",
                targetRect: targetRect(for: rect, center: CGPoint(x: center.x, y: 0.5)),
                source: .local,
                priority: 88
            )
        }

        if rect.area > 0.62 {
            return CaptureGuidance(
                direction: .farther,
                zoomFactor: nil,
                message: "后退一点",
                targetRect: targetRect(for: rect, center: CGPoint(x: 0.5, y: 0.5)),
                source: .local,
                priority: 84
            )
        }

        if rect.area < 0.035 {
            return CaptureGuidance(
                direction: nil,
                zoomFactor: 2,
                message: "切到 2x",
                targetRect: targetRect(for: rect, center: CGPoint(x: 0.5, y: 0.5)),
                source: .local,
                priority: 72
            )
        }

        return CaptureGuidance(
            direction: .hold,
            zoomFactor: nil,
            message: "可以拍",
            targetRect: rect,
            source: .local,
            priority: 20
        )
    }

    private func targetRect(for rect: CGRect, center: CGPoint) -> CGRect {
        let x = min(max(center.x - rect.width / 2, 0.04), max(0.04, 0.96 - rect.width))
        let y = min(max(center.y - rect.height / 2, 0.04), max(0.04, 0.96 - rect.height))
        return CGRect(x: x, y: y, width: rect.width, height: rect.height)
    }
}

struct CompositionSubject {
    var rect: CGRect
    var kind: SubjectKind
}

enum SubjectKind: String {
    case face
    case human
    case object
}

struct CompositionRuleResult: Identifiable {
    var id: String
    var category: CompositionCategory
    var score: Double
    var confidence: Double
    var priority: Int
    var suggestion: String
    var overlay: CompositionOverlay?
}

enum CompositionCategory: String {
    case general
    case portrait
    case landscape
}

enum CompositionOverlay {
    case thirdsGrid
    case subjectBox(CGRect)
    case faceBox(CGRect)
    case horizon(CGFloat)
    case arrow(direction: ArrowDirection, origin: CGPoint)
}

enum ArrowDirection {
    case left
    case right
    case up
    case down
}

struct CaptureGuidance: Equatable {
    var direction: CameraMoveDirection?
    var zoomFactor: CGFloat?
    var message: String
    var targetRect: CGRect?
    var source: GuidanceSource
    var priority: Int

    var isActionable: Bool {
        direction != nil || zoomFactor != nil
    }
}

enum GuidanceSource: String {
    case local
    case ai
}

enum CameraMoveDirection: String {
    case left
    case right
    case up
    case down
    case closer
    case farther
    case hold

    var title: String {
        switch self {
        case .left: return "相机左移"
        case .right: return "相机右移"
        case .up: return "相机上移"
        case .down: return "相机下移"
        case .closer: return "靠近"
        case .farther: return "后退"
        case .hold: return "可以拍"
        }
    }

    var systemImage: String {
        switch self {
        case .left: return "arrow.left"
        case .right: return "arrow.right"
        case .up: return "arrow.up"
        case .down: return "arrow.down"
        case .closer: return "plus"
        case .farther: return "minus"
        case .hold: return "checkmark"
        }
    }
}

extension CGRect {
    var center: CGPoint {
        CGPoint(x: midX, y: midY)
    }

    var area: CGFloat {
        width * height
    }
}
