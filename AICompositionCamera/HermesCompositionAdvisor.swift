import Combine
import Foundation
import UIKit

@MainActor
final class HermesCompositionAdvisor: ObservableObject {
    @Published var isAnalyzing = false
    @Published var advice: String?
    @Published var captureGuidance: CaptureGuidance?
    @Published var recommendedFilterID: String?
    @Published var filterReason: String?
    @Published var errorMessage: String?
    private var activeRequestID = UUID()

    func reset() {
        activeRequestID = UUID()
        isAnalyzing = false
        advice = nil
        captureGuidance = nil
        recommendedFilterID = nil
        filterReason = nil
        errorMessage = nil
    }

    func analyze(image: UIImage?, localResult: CompositionResult?, settings: SettingsStore) async {
        guard settings.hermesMode != .off else { return }
        guard !settings.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = "请先在设置里填写 Hermes API Key。"
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
        recommendedFilterID = nil
        filterReason = nil
        errorMessage = nil

        do {
            let response = try await requestAdvice(
                jpegData: jpegData,
                localContext: localResult?.hermesContext ?? "No local context.",
                aspectRatioTitle: settings.selectedAspectRatio.title,
                apiKey: settings.apiKey,
                apiBaseURL: settings.apiBaseURL,
                model: settings.model
            )
            let parsed = parseResponse(response, localResult: localResult)
            guard activeRequestID == requestID else { return }
            advice = parsed.advice
            captureGuidance = parsed.guidance
            recommendedFilterID = parsed.filterID
            filterReason = parsed.filterReason
        } catch {
            guard activeRequestID == requestID else { return }
            errorMessage = "Hermes 分析失败：\(error.localizedDescription)"
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
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 18

        let imageURL = "data:image/jpeg;base64,\(jpegData.base64EncodedString())"
        let prompt = """
        你是一个实时取景构图教练，目标是像相机取景器提示一样直接指导用户移动手机或调整主体，然后从滤镜库里选出最适合当前画面的滤镜。
        请先判断构图，再判断滤镜。只根据当前取景画面给拍摄前动作，不做照片点评，不说后期修图，不泛泛夸奖。
        优先判断：主体是否明显、主体位置、人物头顶留白、身体裁切、水平线、前景遮挡、拍摄距离、镜头高低、左右移动方向。
        动作必须直接告诉用户移动相机或调整倍率，不要写抽象点评。每条不超过 12 个中文字符。
        移动字段只能填：left、right、up、down、closer、farther、hold。它表示“相机/手机应该往哪里动”，不是主体往哪里动。
        变焦字段只能填数字倍率：0.5、1、1.5、2、3、4、8。没有必要变焦就填 1。
        滤镜必须从可选滤镜里选 1 个，必须返回 filterId，不要返回滤镜中文名。
        当前取景比例：\(aspectRatioTitle)
        本地端侧检测结果：\(localContext)
        可选滤镜：
        \(PhotoFilter.hermesCatalog)
        输出格式必须严格使用五行：
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
    ) -> (advice: String, guidance: CaptureGuidance?, filterID: String?, filterReason: String?) {
        var advice = response.trimmingCharacters(in: .whitespacesAndNewlines)
        var direction: CameraMoveDirection?
        var zoomFactor: CGFloat?
        var filterID: String?
        var filterReason: String?

        for line in response.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("动作：") {
                advice = String(trimmed.dropFirst("动作：".count)).trimmingCharacters(in: .whitespacesAndNewlines)
            } else if trimmed.hasPrefix("建议：") {
                advice = String(trimmed.dropFirst("建议：".count)).trimmingCharacters(in: .whitespacesAndNewlines)
            } else if trimmed.hasPrefix("移动：") {
                let candidate = String(trimmed.dropFirst("移动：".count)).trimmingCharacters(in: .whitespacesAndNewlines)
                direction = parseDirection(candidate)
            } else if trimmed.hasPrefix("方向：") {
                let candidate = String(trimmed.dropFirst("方向：".count)).trimmingCharacters(in: .whitespacesAndNewlines)
                direction = parseDirection(candidate)
            } else if trimmed.hasPrefix("变焦：") {
                let candidate = String(trimmed.dropFirst("变焦：".count)).trimmingCharacters(in: .whitespacesAndNewlines)
                zoomFactor = parseZoomFactor(candidate)
            } else if trimmed.hasPrefix("倍率：") {
                let candidate = String(trimmed.dropFirst("倍率：".count)).trimmingCharacters(in: .whitespacesAndNewlines)
                zoomFactor = parseZoomFactor(candidate)
            } else if trimmed.hasPrefix("滤镜：") {
                let candidate = String(trimmed.dropFirst("滤镜：".count)).trimmingCharacters(in: .whitespacesAndNewlines)
                if let filter = PhotoFilter.matching(candidate) {
                    filterID = filter.id
                }
            } else if trimmed.hasPrefix("原因：") {
                filterReason = String(trimmed.dropFirst("原因：".count)).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        if direction == nil {
            direction = inferDirection(from: advice)
        }

        let meaningfulZoom = zoomFactor.flatMap { abs($0 - 1) < 0.05 ? nil : $0 }
        let guidance: CaptureGuidance?
        if direction != nil || meaningfulZoom != nil {
            guidance = CaptureGuidance(
                direction: direction,
                zoomFactor: meaningfulZoom,
                message: advice,
                targetRect: localResult?.liveGuidance.targetRect ?? localResult?.primarySubject?.rect,
                source: .ai,
                priority: 100
            )
        } else {
            guidance = nil
        }

        return (advice, guidance, filterID, filterReason)
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
        return CGFloat(min(max(number, 0.5), 8))
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
            guard let message, !message.isEmpty else { return "接口返回异常" }
            return "接口返回异常：\(message.prefix(160))"
        case .emptyResponse: return "没有收到建议"
        case .invalidBaseURL: return "中转站地址格式不正确"
        }
    }
}
