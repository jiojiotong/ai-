import Combine
import Foundation
import UIKit

@MainActor
final class HermesCompositionAdvisor: ObservableObject {
    @Published var isAnalyzing = false
    @Published var advice: String?
    @Published var captureGuidance: CaptureGuidance?
    @Published var recognizedSubject: String?
    @Published var recommendedFilterID: String?
    @Published var filterReason: String?
    @Published var errorMessage: String?
    private var activeRequestID = UUID()

    func reset() {
        activeRequestID = UUID()
        isAnalyzing = false
        advice = nil
        captureGuidance = nil
        recognizedSubject = nil
        recommendedFilterID = nil
        filterReason = nil
        errorMessage = nil
    }

    func analyze(image: UIImage?, localResult: CompositionResult?, settings: SettingsStore) async {
        guard settings.hermesMode != .off else { return }
        let apiKey = settings.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard settings.usesHermesPublicGateway || !apiKey.isEmpty else {
            errorMessage = "当前私有网关需要 API Key。"
            return
        }
        guard let image, let jpegData = compressedJPEG(from: image) else {
            errorMessage = "还没有可分析的当前画面。"
            return
        }

        let requestID = UUID()
        activeRequestID = requestID
        isAnalyzing = true
        advice = nil
        captureGuidance = nil
        recognizedSubject = nil
        recommendedFilterID = nil
        filterReason = nil
        errorMessage = nil

        do {
            let response = try await requestAdvice(
                jpegData: jpegData,
                localContext: localResult?.hermesContext ?? "No local context.",
                aspectRatioTitle: settings.selectedAspectRatio.title,
                apiKey: apiKey,
                apiBaseURL: settings.apiBaseURL,
                model: settings.model
            )
            let parsed = parseResponse(response, localResult: localResult)
            guard activeRequestID == requestID else { return }
            advice = parsed.advice
            captureGuidance = parsed.guidance
            recognizedSubject = parsed.subject
            recommendedFilterID = parsed.filterID
            filterReason = parsed.filterReason
        } catch {
            guard activeRequestID == requestID else { return }
            captureGuidance = nil
            errorMessage = friendlyErrorMessage(for: error)
        }

        if activeRequestID == requestID {
            isAnalyzing = false
        }
    }

    private func compressedJPEG(from image: UIImage) -> Data? {
        let maxSide: CGFloat = 768
        let scale = min(1, maxSide / max(image.size.width, image.size.height))
        let targetSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)

        let renderer = UIGraphicsImageRenderer(size: targetSize)
        let resized = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }

        return resized.jpegData(compressionQuality: 0.62)
    }

    private func requestAdvice(
        jpegData: Data,
        localContext: String,
        aspectRatioTitle: String,
        apiKey: String,
        apiBaseURL: String,
        model: String
    ) async throws -> String {
        guard let url = chatCompletionsURL(from: apiBaseURL) else {
            throw HermesError.invalidBaseURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        if !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 18

        let imageURL = "data:image/jpeg;base64,\(jpegData.base64EncodedString())"
        let prompt = """
        你是一个实时取景构图教练，目标是像相机取景器提示一样直接指导用户移动手机或调整主体，然后从滤镜库里选出最适合当前画面的滤镜。
        请先识别用户正在拍的主体，再判断构图和滤镜。只根据当前取景画面给拍摄前动作，不做照片点评，不说后期修图，不泛泛夸奖。
        重要：不要默认回复“可以拍”。除非主体位置、边缘留白、水平线、曝光和拍摄距离都明显稳定，否则必须给一个最小可执行微调动作。
        如果画面变化了，即使本地端侧检测结果相似，也要重新观察当前帧并给当前帧建议。
        优先判断：主体是否明显、主体位置、人物头顶留白、身体裁切、水平线、前景遮挡、拍摄距离、镜头高低、左右移动方向。
        动作必须直接告诉用户移动相机或调整倍率，不要写抽象点评。每条不超过 12 个中文字符。
        如果主体不是明显居中，或左右/上下留白不均衡，不要返回 hold。hold 只用于主体清晰、位置舒服、边缘不贴边、画面已经适合按快门。
        如果当前帧无法可靠判断，也不要假装可以拍；动作写“重新取景”，移动填 hold，原因写“画面主体不明确”。
        对矿泉水瓶、杯子、鼠标、食物、摆件等小物体，优先让主体放到画面中心或略低于中心，并明确说相机往哪移或切几倍。
        移动字段只能填：left、right、up、down、closer、farther、hold。它表示“相机/手机应该往哪里动”，不是主体往哪里动。
        变焦字段只能填数字倍率：0.5、1、1.5、2、3、4、8。没有必要变焦就填 1。
        滤镜必须从可选滤镜里选 1 个，必须返回 filterId，不要返回滤镜中文名。
        禁止返回 JSON 预设名作为滤镜：natural_clean、portrait_soft、food_warm、product_neutral、night_neon、film_matte、cinematic_teal_orange、travel_vivid、bw_graphic 都不是本 App 的 filterId。
        也禁止返回 camelCase 伪 ID：naturalClean、portraitSoft、foodWarm、productNeutral、nightNeon、filmMatte、cinematicTealOrange、travelVivid、bwGraphic 都不是本 App 的 filterId。
        当前取景比例：\(aspectRatioTitle)
        本地端侧检测结果：\(localContext)
        可选滤镜：
        \(PhotoFilter.hermesCatalog)
        输出格式必须严格使用六行：
        主体：矿泉水瓶/鼠标/人脸/人物/杯子/未识别主体
        动作：...
        移动：left/right/up/down/closer/farther/hold
        变焦：数字倍率
        滤镜：filterId
        原因：为什么这个滤镜适合当前取景
        """

        let body: [String: Any] = [
            "model": model.isEmpty ? "ai-camera-agent" : model,
            "messages": [
                [
                    "role": "user",
                    "content": [
                        ["type": "text", "text": prompt],
                        ["type": "image_url", "image_url": ["url": imageURL]]
                    ]
                ]
            ],
            "max_tokens": 140,
            "temperature": 0.25
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
            let message = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw HermesError.badResponse(message)
        }

        let decoded = try JSONDecoder().decode(HermesChatResponse.self, from: data)
        guard let content = decoded.choices.first?.message.content.trimmingCharacters(in: .whitespacesAndNewlines), !content.isEmpty else {
            throw HermesError.emptyResponse
        }
        return content
    }

    private func friendlyErrorMessage(for error: Error) -> String {
        if let hermesError = error as? HermesError {
            switch hermesError {
            case .invalidBaseURL:
                return hermesError.localizedDescription
            case .emptyResponse, .badResponse(_):
                return "Hermes 暂不可用，已用本地指导"
            }
        }

        return "Hermes 暂不可用，已用本地指导"
    }

    private func chatCompletionsURL(from apiBaseURL: String) -> URL? {
        let trimmed = apiBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let baseURLString = trimmed.isEmpty ? "https://api.anyther.top/hermes-ai-camera/v1" : trimmed
        guard let baseURL = URL(string: baseURLString), let scheme = baseURL.scheme, !scheme.isEmpty else {
            return nil
        }

        if baseURL.path.hasSuffix("/chat/completions") {
            return baseURL
        }

        return baseURL
            .appendingPathComponent("chat")
            .appendingPathComponent("completions")
    }

    private func parseResponse(
        _ response: String,
        localResult: CompositionResult?
    ) -> (advice: String, subject: String?, guidance: CaptureGuidance?, filterID: String?, filterReason: String?) {
        var advice = response.trimmingCharacters(in: .whitespacesAndNewlines)
        var subject: String?
        var direction: CameraMoveDirection?
        var zoomFactor: CGFloat?
        var filterID: String?
        var filterReason: String?
        var extractedValues: [String: String] = [:]

        for line in response.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            if let pair = labeledValue(from: trimmed) {
                extractedValues[pair.label] = pair.value
            }
        }

        if let jsonValues = jsonResponseValues(from: response) {
            extractedValues.merge(jsonValues) { _, jsonValue in jsonValue }
        }

        subject = extractedValues["主体"] ?? extractedValues["识别"] ?? extractedValues["subject"] ?? subject
        advice = extractedValues["动作"] ?? extractedValues["建议"] ?? extractedValues["action"] ?? extractedValues["framing_action"] ?? advice

        if let candidate = extractedValues["移动"] ?? extractedValues["方向"] ?? extractedValues["move"] ?? extractedValues["direction"] ?? extractedValues["camera_move"] {
            direction = parseDirection(candidate)
        }

        if let candidate = extractedValues["变焦"] ?? extractedValues["倍率"] ?? extractedValues["zoom"] ?? extractedValues["zoom_factor"] {
            zoomFactor = parseZoomFactor(candidate)
        }

        if let candidate = extractedValues["滤镜"] ?? extractedValues["filter"] ?? extractedValues["filterId"] ?? extractedValues["filter_id"],
           let filter = PhotoFilter.matching(candidate) {
            filterID = filter.id
        }

        filterReason = extractedValues["原因"] ?? extractedValues["reason"] ?? extractedValues["rationale"] ?? filterReason
        advice = sanitizedAdvice(advice)

        if direction == nil {
            direction = inferDirection(from: advice)
        }

        let corrected = correctedGuidance(
            direction: direction,
            zoomFactor: zoomFactor,
            advice: advice,
            localResult: localResult
        )
        direction = corrected.direction
        zoomFactor = corrected.zoomFactor
        advice = corrected.advice

        let meaningfulZoom = zoomFactor.flatMap { abs($0 - 1) < 0.05 ? nil : $0 }
        let guidance: CaptureGuidance?
        if direction != nil || meaningfulZoom != nil {
            guidance = CaptureGuidance(
                direction: direction,
                zoomFactor: meaningfulZoom,
                message: displayMessage(subject: subject, advice: advice, direction: direction),
                targetRect: localResult?.liveGuidance.targetRect ?? localResult?.primarySubject?.rect,
                source: .ai,
                priority: 100
            )
        } else {
            guidance = nil
        }

        return (advice, sanitizedSubject(subject), guidance, filterID, filterReason)
    }

    private func labeledValue(from line: String) -> (label: String, value: String)? {
        let separators = ["：", ":"]
        for separator in separators {
            guard let range = line.range(of: separator) else { continue }
            let label = String(line[..<range.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'` "))
            let value = String(line[range.upperBound...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'`,， "))
            guard !label.isEmpty, !value.isEmpty else { return nil }
            return (label, value)
        }
        return nil
    }

    private func jsonResponseValues(from response: String) -> [String: String]? {
        let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let start = trimmed.firstIndex(of: "{"),
              let end = trimmed.lastIndex(of: "}"),
              start <= end else { return nil }

        let jsonText = String(trimmed[start...end])
        guard let data = jsonText.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        var values: [String: String] = [:]
        for (key, value) in object {
            if let string = value as? String {
                values[key] = string
            } else if let number = value as? NSNumber {
                values[key] = number.stringValue
            }
        }
        return values
    }

    private func correctedGuidance(
        direction: CameraMoveDirection?,
        zoomFactor: CGFloat?,
        advice: String,
        localResult: CompositionResult?
    ) -> (direction: CameraMoveDirection?, zoomFactor: CGFloat?, advice: String) {
        guard let localGuidance = localResult?.liveGuidance else {
            return (direction, zoomFactor, advice)
        }

        let localDirection = localGuidance.direction
        let localIsAction = localDirection != nil && localDirection != .hold
        let aiSaysHold = direction == .hold || (direction == nil && zoomFactor == nil)

        guard aiSaysHold else {
            return (direction, zoomFactor, advice)
        }

        if localIsAction {
            return (
                localDirection,
                localGuidance.zoomFactor ?? zoomFactor,
                localGuidance.message
            )
        }

        if let microGuidance = microGuidance(from: localResult) {
            return (
                microGuidance.direction,
                microGuidance.zoomFactor ?? zoomFactor,
                microGuidance.message
            )
        }

        return (direction, zoomFactor, advice)
    }

    private func microGuidance(from localResult: CompositionResult?) -> CaptureGuidance? {
        guard let subject = localResult?.primarySubject else { return nil }
        let rect = subject.rect
        let center = rect.center

        if center.x < 0.43 {
            return CaptureGuidance(
                direction: .left,
                zoomFactor: nil,
                message: "相机左移",
                targetRect: targetRect(for: rect, center: CGPoint(x: 0.5, y: center.y)),
                source: .ai,
                priority: 96
            )
        }

        if center.x > 0.57 {
            return CaptureGuidance(
                direction: .right,
                zoomFactor: nil,
                message: "相机右移",
                targetRect: targetRect(for: rect, center: CGPoint(x: 0.5, y: center.y)),
                source: .ai,
                priority: 96
            )
        }

        if center.y < 0.40 {
            return CaptureGuidance(
                direction: .up,
                zoomFactor: nil,
                message: "相机上移",
                targetRect: targetRect(for: rect, center: CGPoint(x: center.x, y: 0.5)),
                source: .ai,
                priority: 94
            )
        }

        if center.y > 0.62 {
            return CaptureGuidance(
                direction: .down,
                zoomFactor: nil,
                message: "相机下移",
                targetRect: targetRect(for: rect, center: CGPoint(x: center.x, y: 0.5)),
                source: .ai,
                priority: 94
            )
        }

        if rect.area < 0.06 {
            return CaptureGuidance(
                direction: nil,
                zoomFactor: 2,
                message: "切到 2x",
                targetRect: targetRect(for: rect, center: CGPoint(x: 0.5, y: 0.5)),
                source: .ai,
                priority: 88
            )
        }

        return nil
    }

    private func targetRect(for rect: CGRect, center: CGPoint) -> CGRect {
        let x = min(max(center.x - rect.width / 2, 0.04), max(0.04, 0.96 - rect.width))
        let y = min(max(center.y - rect.height / 2, 0.04), max(0.04, 0.96 - rect.height))
        return CGRect(x: x, y: y, width: rect.width, height: rect.height)
    }

    private func displayMessage(subject: String?, advice: String, direction: CameraMoveDirection?) -> String {
        let cleanSubject = sanitizedSubject(subject)
        let cleanAdvice = advice.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let cleanSubject, !cleanAdvice.contains(cleanSubject) else {
            return cleanAdvice
        }

        if direction == .hold {
            return "识别：\(cleanSubject)，\(cleanAdvice.isEmpty ? "可以拍" : cleanAdvice)"
        }

        return "识别：\(cleanSubject)，\(cleanAdvice)"
    }

    private func sanitizedSubject(_ value: String?) -> String? {
        guard let value else { return nil }
        let cleaned = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "。", with: "")
        guard !cleaned.isEmpty, cleaned != "未识别主体" else { return nil }
        return String(cleaned.prefix(18))
    }

    private func sanitizedAdvice(_ value: String) -> String {
        let cleaned = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'`。，, "))
        guard !cleaned.isEmpty else { return cleaned }
        return String(cleaned.prefix(12))
    }

    private func parseDirection(_ value: String) -> CameraMoveDirection? {
        let normalized = value
            .lowercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "camera", with: "")
            .replacingOccurrences(of: "phone", with: "")
            .replacingOccurrences(of: "相机", with: "")
            .replacingOccurrences(of: "手机", with: "")
            .replacingOccurrences(of: "镜头", with: "")

        if normalized.contains("left") || normalized.contains("左") { return .left }
        if normalized.contains("right") || normalized.contains("右") { return .right }
        if normalized.contains("up") || normalized.contains("上") || normalized.contains("抬") { return .up }
        if normalized.contains("down") || normalized.contains("下") || normalized.contains("低") { return .down }
        if normalized.contains("closer") || normalized.contains("near") || normalized.contains("靠近") || normalized.contains("拉近") { return .closer }
        if normalized.contains("farther") || normalized.contains("back") || normalized.contains("后退") || normalized.contains("远") { return .farther }
        if normalized.contains("hold") || normalized.contains("ok") || normalized.contains("保持") || normalized.contains("可以") { return .hold }
        return CameraMoveDirection(rawValue: normalized)
    }

    private func inferDirection(from advice: String) -> CameraMoveDirection? {
        if advice.contains("左") { return .left }
        if advice.contains("右") { return .right }
        if advice.contains("上") || advice.contains("抬") { return .up }
        if advice.contains("下") || advice.contains("低") { return .down }
        if advice.contains("靠近") || advice.contains("拉近") || advice.contains("放大") { return .closer }
        if advice.contains("后退") || advice.contains("远") || advice.contains("缩小") { return .farther }
        if advice.contains("可以拍") || advice.contains("保持") { return .hold }
        return nil
    }

    private func parseZoomFactor(_ value: String) -> CGFloat? {
        let cleaned = value
            .lowercased()
            .replacingOccurrences(of: "x", with: "")
            .replacingOccurrences(of: "倍", with: "")
            .replacingOccurrences(of: "倍率", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let number = Double(cleaned) else { return nil }
        let supported = [0.5, 1, 1.5, 2, 3, 4, 8]
        let nearest = supported.min { lhs, rhs in
            abs(lhs - number) < abs(rhs - number)
        } ?? 1
        return CGFloat(nearest)
    }
}

private struct HermesChatResponse: Decodable {
    var choices: [Choice]

    struct Choice: Decodable {
        var message: Message
    }

    struct Message: Decodable {
        var content: String
    }
}

private enum HermesError: LocalizedError {
    case badResponse(String?)
    case emptyResponse
    case invalidBaseURL

    var errorDescription: String? {
        switch self {
        case .badResponse(let message):
            guard let message, !message.isEmpty else { return "Hermes 暂不可用" }
            return "Hermes 暂不可用：\(message.prefix(120))"
        case .emptyResponse: return "没有收到建议"
        case .invalidBaseURL: return "中转站地址格式不正确"
        }
    }
}
