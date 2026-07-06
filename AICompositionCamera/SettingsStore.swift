import Combine
import Foundation

final class SettingsStore: ObservableObject {
    @Published var gptMode: GPTMode {
        didSet { UserDefaults.standard.set(gptMode.rawValue, forKey: Keys.gptMode) }
    }

    @Published var automaticGPTInterval: TimeInterval {
        didSet { UserDefaults.standard.set(automaticGPTInterval, forKey: Keys.automaticGPTInterval) }
    }

    @Published var overlayIntensity: OverlayIntensity {
        didSet { UserDefaults.standard.set(overlayIntensity.rawValue, forKey: Keys.overlayIntensity) }
    }

    @Published var apiKey: String {
        didSet {
            KeychainStore.save(apiKey, service: Keys.keychainService, account: Keys.apiKey)
        }
    }

    @Published var model: String {
        didSet { UserDefaults.standard.set(model, forKey: Keys.model) }
    }

    @Published var selectedFilterID: String {
        didSet { UserDefaults.standard.set(selectedFilterID, forKey: Keys.selectedFilterID) }
    }

    init() {
        let defaults = UserDefaults.standard
        gptMode = GPTMode(rawValue: defaults.string(forKey: Keys.gptMode) ?? "manual") ?? .manual
        automaticGPTInterval = defaults.object(forKey: Keys.automaticGPTInterval) as? TimeInterval ?? 10
        overlayIntensity = OverlayIntensity(rawValue: defaults.string(forKey: Keys.overlayIntensity) ?? "normal") ?? .normal
        apiKey = KeychainStore.read(service: Keys.keychainService, account: Keys.apiKey)
        model = defaults.string(forKey: Keys.model) ?? "gpt-4o"
        selectedFilterID = defaults.string(forKey: Keys.selectedFilterID) ?? PhotoFilter.fallback.id
    }
}

enum GPTMode: String, CaseIterable, Identifiable {
    case off
    case manual
    case automatic
    case manualAndAutomatic

    var id: String { rawValue }

    var title: String {
        switch self {
        case .off: return "关闭"
        case .manual: return "手动"
        case .automatic: return "自动"
        case .manualAndAutomatic: return "手动 + 自动"
        }
    }

    var allowsManual: Bool {
        self == .manual || self == .manualAndAutomatic
    }

    var allowsAutomatic: Bool {
        self == .automatic || self == .manualAndAutomatic
    }
}

enum OverlayIntensity: String, CaseIterable, Identifiable {
    case minimal
    case normal
    case detailed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .minimal: return "极简"
        case .normal: return "标准"
        case .detailed: return "详细"
        }
    }
}

private enum Keys {
    static let gptMode = "gptMode"
    static let automaticGPTInterval = "automaticGPTInterval"
    static let overlayIntensity = "overlayIntensity"
    static let apiKey = "openAIAPIKey"
    static let model = "openAIModel"
    static let selectedFilterID = "selectedFilterID"
    static let keychainService = "AICompositionCamera"
}
