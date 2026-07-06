import CoreGraphics

final class CompositionEngine {
    func evaluate(observations: VisionObservations) -> CompositionResult {
        let subject = primarySubject(from: observations)
        var rules: [CompositionRuleResult] = [
            CompositionRuleResult(
                id: "thirds-grid",
                category: .general,
                score: 1,
                confidence: 1,
                priority: 0,
                suggestion: "",
                overlay: .thirdsGrid
            )
        ]

        if let subject {
            rules.append(contentsOf: generalRules(for: subject))
        } else {
            rules.append(CompositionRuleResult(
                id: "find-subject",
                category: .general,
                score: 0.45,
                confidence: 0.55,
                priority: 60,
                suggestion: "让主体更明显一些，靠近人物或主要物体。",
                overlay: nil
            ))
        }

        if let face = observations.faces.first {
            rules.append(contentsOf: portraitRules(face: face))
        }

        return CompositionResult(
            rules: rules,
            primarySubject: subject,
            imageAspectRatio: observations.displayAspectRatio
        )
    }

    private func primarySubject(from observations: VisionObservations) -> CompositionSubject? {
        if let face = observations.faces.sorted(by: { $0.area > $1.area }).first {
            return CompositionSubject(rect: face, kind: .face)
        }

        if let human = observations.humans.sorted(by: { $0.area > $1.area }).first {
            return CompositionSubject(rect: human, kind: .human)
        }

        if let object = observations.salientObjects.sorted(by: { $0.area > $1.area }).first {
            return CompositionSubject(rect: object, kind: .object)
        }

        return nil
    }

    private func generalRules(for subject: CompositionSubject) -> [CompositionRuleResult] {
        var rules: [CompositionRuleResult] = [
            CompositionRuleResult(
                id: "subject-box",
                category: .general,
                score: 1,
                confidence: 0.9,
                priority: 1,
                suggestion: "",
                overlay: subject.kind == .face ? .faceBox(subject.rect) : .subjectBox(subject.rect)
            )
        ]

        let center = subject.rect.center
        let nearestThirdX = nearest(center.x, in: [CGFloat(1.0 / 3.0), CGFloat(2.0 / 3.0), 0.5])
        let horizontalDistance = abs(center.x - nearestThirdX)

        if horizontalDistance > 0.12 {
            let direction: ArrowDirection = center.x < 0.5 ? .right : .left
            rules.append(CompositionRuleResult(
                id: "thirds-alignment",
                category: .general,
                score: Double(max(0, 1 - horizontalDistance * 2.5)),
                confidence: 0.72,
                priority: 70,
                suggestion: center.x < 0.5 ? "主体稍微向右一点，画面会更稳。" : "主体稍微向左一点，画面会更稳。",
                overlay: .arrow(direction: direction, origin: center)
            ))
        }

        if subject.rect.area < 0.05 {
            rules.append(CompositionRuleResult(
                id: "subject-too-small",
                category: .general,
                score: 0.45,
                confidence: 0.68,
                priority: 78,
                suggestion: "主体有点小，可以靠近一点或拉近焦距。",
                overlay: .arrow(direction: .up, origin: center)
            ))
        }

        if subject.rect.minX < 0.05 || subject.rect.maxX > 0.95 {
            rules.append(CompositionRuleResult(
                id: "subject-edge",
                category: .general,
                score: 0.5,
                confidence: 0.74,
                priority: 82,
                suggestion: "主体太贴边了，给边缘留一点呼吸感。",
                overlay: .subjectBox(subject.rect)
            ))
        }

        return rules
    }

    private func portraitRules(face: CGRect) -> [CompositionRuleResult] {
        var rules: [CompositionRuleResult] = []
        let eyeLineY = face.minY + face.height * 0.38

        if eyeLineY > 0.48 {
            rules.append(CompositionRuleResult(
                id: "eye-line-low",
                category: .portrait,
                score: 0.55,
                confidence: 0.64,
                priority: 74,
                suggestion: "镜头稍微抬高一点，让眼睛接近上三分线。",
                overlay: .arrow(direction: .up, origin: face.center)
            ))
        }

        if face.minY < 0.05 {
            rules.append(CompositionRuleResult(
                id: "headroom-tight",
                category: .portrait,
                score: 0.5,
                confidence: 0.76,
                priority: 86,
                suggestion: "头顶空间太紧，镜头稍微向上留一点。",
                overlay: .faceBox(face)
            ))
        }

        return rules
    }

    private func nearest(_ value: CGFloat, in candidates: [CGFloat]) -> CGFloat {
        candidates.min { abs($0 - value) < abs($1 - value) } ?? value
    }
}

private extension CGRect {
    var area: CGFloat {
        width * height
    }
}
