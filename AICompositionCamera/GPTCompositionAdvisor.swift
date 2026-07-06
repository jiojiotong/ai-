import Combine
import Foundation
import UIKit

@MainActor
final class GPTCompositionAdvisor: ObservableObject {
    @Published var isAnalyzing = false
    @Published var advice: String?
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
                model: settings.model
            )
            advice = response
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

    private func requestAdvice(jpegData: Data, localContext: String, apiKey: String, model: String) async throws -> String {
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 18

        let imageURL = "data:image/jpeg;base64,\(jpegData.base64EncodedString())"
        let prompt = """
        你是一个实时摄影构图教练。请根据当前取景画面给 1 到 3 条简短中文建议。
        要求：只给拍摄前的构图建议，不要说后期修图；优先给移动镜头、调整主体位置、水平线、留白、角度相关建议；每条不超过 24 个中文字符。
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

    var errorDescription: String? {
        switch self {
        case .badResponse: return "接口返回异常"
        case .emptyResponse: return "没有收到建议"
        }
    }
}
