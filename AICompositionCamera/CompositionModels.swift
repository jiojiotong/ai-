import CoreGraphics

struct VisionObservations {
    var faces: [CGRect]
    var humans: [CGRect]
    var salientObjects: [CGRect]
    var frameSize: CGSize
}

struct CompositionResult {
    var rules: [CompositionRuleResult]
    var primarySubject: CompositionSubject?

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
