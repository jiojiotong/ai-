import Combine
import Foundation
import UIKit

@MainActor
final class GPTCompositionAdvisor: ObservableObject {
    @Published var isAnalyzing = false
    @Published var advice: String?
    @Published var recommendedFilterID: String?
    @Published var filterReason: String?
    @Published var errorMessage: String?

    func analyze(image: UIImage?, localResult: CompositionResult?, settings: SettingsStore) async {
        guard settings.gptMode != .off else { return }
        guard !settings.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = "请先在设置里填写 OpenAI API Key。"
            return
        }
        guard let image, let jpegData = compressedJPEG(from: image) else {
            errorMessage = "还没有可分析的当前画面。"
            return
        }

        isAnalyzing = true
        advice = nil
        recommendedFilterID = nil
        filterReason = nil
        errorMessage = nil

        do {
            let response = try await requestAdvice(
                jpegData: jpegData,
                localContext: localResult?.gptContext ?? "No local context.",
                aspectRatioTitle: settings.selectedAspectRatio.title,
                apiKey: settings.apiKey,
                apiBaseURL: settings.apiBaseURL,
                model: settings.model
            )
            let parsed = parseResponse(response)
            advice = parsed.advice
            recommendedFilterID = parsed.filterID
            filterReason = parsed.filterReason
        } catch {
            errorMessage = "GPT 分析失败：\(error.localizedDescription)"
        }

        isAnalyzing = false
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
            throw GPTError.invalidBaseURL
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
        动作必须是用户马上能执行的指令，每条不超过 22 个中文字符。
        滤镜必须从可选滤镜里选 1 个，必须返回 filterId，不要返回滤镜中文名。
        当前取景比例：\(aspectRatioTitle)
        本地端侧检测结果：\(localContext)
        可选滤镜：
        \(PhotoFilter.gptCatalog)
        输出格式必须严格使用三行：
        动作：...
        滤镜：filterId
        原因：为什么这个滤镜适合当前取景
        """

        let body: [String: Any] = [
            "model": model.isEmpty ? "gpt-4o" : model,
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
            throw GPTError.badResponse(message)
        }

        let decoded = try JSONDecoder().decode(OpenAIChatResponse.self, from: data)
        guard let content = decoded.choices.first?.message.content.trimmingCharacters(in: .whitespacesAndNewlines), !content.isEmpty else {
            throw GPTError.emptyResponse
        }
        return content
    }

    private func chatCompletionsURL(from apiBaseURL: String) -> URL? {
        let trimmed = apiBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let baseURLString = trimmed.isEmpty ? "https://api.openai.com/v1" : trimmed
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

    private func parseResponse(_ response: String) -> (advice: String, filterID: String?, filterReason: String?) {
        var advice = response.trimmingCharacters(in: .whitespacesAndNewlines)
        var filterID: String?
        var filterReason: String?

        for line in response.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("动作：") {
                advice = String(trimmed.dropFirst("动作：".count)).trimmingCharacters(in: .whitespacesAndNewlines)
            } else if trimmed.hasPrefix("建议：") {
                advice = String(trimmed.dropFirst("建议：".count)).trimmingCharacters(in: .whitespacesAndNewlines)
            } else if trimmed.hasPrefix("滤镜：") {
                let candidate = String(trimmed.dropFirst("滤镜：".count)).trimmingCharacters(in: .whitespacesAndNewlines)
                if let filter = PhotoFilter.matching(candidate) {
                    filterID = filter.id
                }
            } else if trimmed.hasPrefix("原因：") {
                filterReason = String(trimmed.dropFirst("原因：".count)).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        return (advice, filterID, filterReason)
    }
}

private struct OpenAIChatResponse: Decodable {
    var choices: [Choice]

    struct Choice: Decodable {
        var message: Message
    }

    struct Message: Decodable {
        var content: String
    }
}

private enum GPTError: LocalizedError {
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
