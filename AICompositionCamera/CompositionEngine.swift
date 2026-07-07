import CoreGraphics

final class CompositionEngine {
    func evaluate(observations: VisionObservations) -> CompositionResult {
        let subject = primarySubject(from: observations)
        var rules: [CompositionRuleResult] = []

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

        if let human = observations.humans.sorted(by: { $0.area > $1.area }).first {
            rules.append(contentsOf: bodyRules(human: human))
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

        if subject.rect.area > 0.62 {
            rules.append(CompositionRuleResult(
                id: "subject-too-large",
                category: .general,
                score: 0.52,
                confidence: 0.66,
                priority: 76,
                suggestion: "主体占比偏满，稍微后退一点。",
                overlay: .subjectBox(subject.rect)
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

        if subject.rect.minY < 0.04 || subject.rect.maxY > 0.96 {
            rules.append(CompositionRuleResult(
                id: "subject-vertical-edge",
                category: .general,
                score: 0.55,
                confidence: 0.7,
                priority: 80,
                suggestion: "上下边缘太紧，给主体多留一点空间。",
                overlay: .subjectBox(subject.rect)
            ))
        }

        let nearestThirdY = nearest(center.y, in: [CGFloat(1.0 / 3.0), CGFloat(2.0 / 3.0), 0.5])
        let verticalDistance = abs(center.y - nearestThirdY)
        if verticalDistance > 0.17 {
            rules.append(CompositionRuleResult(
                id: "vertical-balance",
                category: .general,
                score: Double(max(0, 1 - verticalDistance * 2.2)),
                confidence: 0.58,
                priority: 58,
                suggestion: "调整上下留白，让主体更接近三分线。",
                overlay: .arrow(direction: center.y < 0.5 ? .down : .up, origin: center)
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

        if eyeLineY < 0.22 {
            rules.append(CompositionRuleResult(
                id: "eye-line-high",
                category: .portrait,
                score: 0.58,
                confidence: 0.62,
                priority: 68,
                suggestion: "眼睛位置偏高，镜头稍微降低一点。",
                overlay: .arrow(direction: .down, origin: face.center)
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

        if face.minY > 0.2 {
            rules.append(CompositionRuleResult(
                id: "headroom-loose",
                category: .portrait,
                score: 0.62,
                confidence: 0.6,
                priority: 62,
                suggestion: "头顶留白偏多，可以稍微靠近一点。",
                overlay: .faceBox(face)
            ))
        }

        if face.minX < 0.07 || face.maxX > 0.93 {
            rules.append(CompositionRuleResult(
                id: "face-edge",
                category: .portrait,
                score: 0.56,
                confidence: 0.72,
                priority: 84,
                suggestion: "脸太靠边了，给侧脸留一点空间。",
                overlay: .faceBox(face)
            ))
        }

        return rules
    }

    private func bodyRules(human: CGRect) -> [CompositionRuleResult] {
        var rules: [CompositionRuleResult] = []

        if human.minY < 0.02 || human.maxY > 0.98 {
            rules.append(CompositionRuleResult(
                id: "body-vertical-crop",
                category: .portrait,
                score: 0.5,
                confidence: 0.7,
                priority: 83,
                suggestion: "人物上下快被裁掉了，稍微后退一点。",
                overlay: .subjectBox(human)
            ))
        }

        if human.minX < 0.03 || human.maxX > 0.97 {
            rules.append(CompositionRuleResult(
                id: "body-horizontal-crop",
                category: .portrait,
                score: 0.52,
                confidence: 0.68,
                priority: 79,
                suggestion: "人物侧边太紧，镜头稍微挪开一点。",
                overlay: .subjectBox(human)
            ))
        }

        return rules
    }

    private func nearest(_ value: CGFloat, in candidates: [CGFloat]) -> CGFloat {
        candidates.min { abs($0 - value) < abs($1 - value) } ?? value
    }
}
