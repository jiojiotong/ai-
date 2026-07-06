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
        errorMessage = nil

        do {
            let response = try await requestAdvice(
                jpegData: jpegData,
                localContext: localResult?.gptContext ?? "No local context.",
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
        你是一个实时摄影构图教练。请根据当前取景画面给 1 到 3 条简短中文建议，并从允许的滤镜中推荐 1 个。
        要求：只给拍摄前的构图建议，不要说后期修图；优先给移动镜头、调整主体位置、水平线、留白、角度相关建议；建议每条不超过 24 个中文字符。
        输出格式必须严格使用三行：
        建议：...
        滤镜：filterId
        原因：...
        可选滤镜：
        \(PhotoFilter.gptCatalog)
        本地端侧检测结果：\(localContext)
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
            "max_tokens": 180,
            "temperature": 0.35
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
            throw GPTError.badResponse
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
            if trimmed.hasPrefix("建议：") {
                advice = String(trimmed.dropFirst("建议：".count)).trimmingCharacters(in: .whitespacesAndNewlines)
            } else if trimmed.hasPrefix("滤镜：") {
                let candidate = String(trimmed.dropFirst("滤镜：".count)).trimmingCharacters(in: .whitespacesAndNewlines)
                if PhotoFilter.all.contains(where: { $0.id == candidate }) {
                    filterID = candidate
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
    case badResponse
    case emptyResponse
    case invalidBaseURL

    var errorDescription: String? {
        switch self {
        case .badResponse: return "接口返回异常"
        case .emptyResponse: return "没有收到建议"
        case .invalidBaseURL: return "中转站地址格式不正确"
        }
    }
}
