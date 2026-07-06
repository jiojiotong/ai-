import CoreGraphics

struct VisionObservations {
    var faces: [CGRect]
    var humans: [CGRect]
    var salientObjects: [CGRect]
    var frameSize: CGSize

    var displayAspectRatio: CGFloat {
        guard frameSize.width > 0 else { return 9.0 / 16.0 }
        // Camera buffers are analyzed in portrait via `.right` orientation.
        return frameSize.height / frameSize.width
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

    var gptContext: String {
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

extension CGRect {
    var center: CGPoint {
        CGPoint(x: midX, y: midY)
    }
}
