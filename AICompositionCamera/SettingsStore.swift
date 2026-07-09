import Combine
import CoreGraphics
import Foundation

final class SettingsStore: ObservableObject {
    static let hermesCameraBaseURL = "https://api.anyther.top/hermes-ai-camera/v1"
    static let hermesCameraModel = "ai-camera-agent"

    @Published var hermesMode: HermesMode {
        didSet { UserDefaults.standard.set(hermesMode.rawValue, forKey: Keys.hermesMode) }
    }

    @Published var automaticHermesInterval: TimeInterval {
        didSet { UserDefaults.standard.set(automaticHermesInterval, forKey: Keys.automaticHermesInterval) }
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

    @Published var apiBaseURL: String {
        didSet { UserDefaults.standard.set(apiBaseURL, forKey: Keys.apiBaseURL) }
    }

    @Published var selectedFilterID: String {
        didSet {
            UserDefaults.standard.set(selectedFilterID, forKey: Keys.selectedFilterID)
            let category = PhotoFilter.filter(for: selectedFilterID).category
            if selectedFilterCategory != category {
                selectedFilterCategory = category
            }
        }
    }

    @Published var selectedFilterCategory: FilterCategory {
        didSet {
            UserDefaults.standard.set(selectedFilterCategory.rawValue, forKey: Keys.selectedFilterCategory)
            applyFirstFilter(in: selectedFilterCategory)
        }
    }

    @Published var selectedPortraitEnhancementID: String {
        didSet {
            UserDefaults.standard.set(selectedPortraitEnhancementID, forKey: Keys.selectedPortraitEnhancementID)
            let enhancement = PortraitEnhancement.enhancement(for: selectedPortraitEnhancementID)
            selectedFilterID = enhancement.filterID
            selectedFilterCategory = PhotoFilter.filter(for: enhancement.filterID).category
        }
    }

    @Published var selectedAspectRatio: ShootingAspectRatio {
        didSet { UserDefaults.standard.set(selectedAspectRatio.rawValue, forKey: Keys.selectedAspectRatio) }
    }

    init() {
        let defaults = UserDefaults.standard
        hermesMode = HermesMode(rawValue: defaults.string(forKey: Keys.hermesMode) ?? "manualAndAutomatic") ?? .manualAndAutomatic
        automaticHermesInterval = defaults.object(forKey: Keys.automaticHermesInterval) as? TimeInterval ?? 5
        overlayIntensity = OverlayIntensity(rawValue: defaults.string(forKey: Keys.overlayIntensity) ?? "normal") ?? .normal
        let hermesKey = KeychainStore.read(service: Keys.keychainService, account: Keys.apiKey)
        apiKey = hermesKey
        let storedModel = defaults.string(forKey: Keys.model) ?? defaults.string(forKey: LegacyKeys.model)
        model = storedModel == nil || storedModel == "gpt-4o" ? Self.hermesCameraModel : storedModel ?? Self.hermesCameraModel
        let storedBaseURL = defaults.string(forKey: Keys.apiBaseURL) ?? defaults.string(forKey: LegacyKeys.apiBaseURL)
        apiBaseURL = storedBaseURL == nil || storedBaseURL == "https://api.openai.com/v1" ? Self.hermesCameraBaseURL : storedBaseURL ?? Self.hermesCameraBaseURL
        selectedFilterID = defaults.string(forKey: Keys.selectedFilterID) ?? PhotoFilter.fallback.id
        selectedFilterCategory = FilterCategory(rawValue: defaults.string(forKey: Keys.selectedFilterCategory) ?? "portrait") ?? .portrait
        selectedPortraitEnhancementID = defaults.string(forKey: Keys.selectedPortraitEnhancementID) ?? PortraitEnhancement.natural.id
        selectedAspectRatio = ShootingAspectRatio(rawValue: defaults.string(forKey: Keys.selectedAspectRatio) ?? "full") ?? .full

        defaults.set(model, forKey: Keys.model)
        defaults.set(apiBaseURL, forKey: Keys.apiBaseURL)
        if !apiKey.isEmpty {
            KeychainStore.save(apiKey, service: Keys.keychainService, account: Keys.apiKey)
        }
    }

    func useHermesCameraBrain() {
        apiBaseURL = Self.hermesCameraBaseURL
        model = Self.hermesCameraModel
        if hermesMode == .off {
            hermesMode = .manual
        }
    }

    var isUsingHermesCameraBrain: Bool {
        apiBaseURL.trimmingCharacters(in: .whitespacesAndNewlines) == Self.hermesCameraBaseURL &&
        model.trimmingCharacters(in: .whitespacesAndNewlines) == Self.hermesCameraModel
    }

    var usesHermesPublicGateway: Bool {
        let normalized = apiBaseURL
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return normalized == Self.hermesCameraBaseURL || normalized.contains("api.anyther.top/hermes-ai-camera")
    }

    private func applyFirstFilter(in category: FilterCategory) {
        guard selectedFilterCategory == category else { return }
        guard PhotoFilter.filter(for: selectedFilterID).category != category else { return }
        selectedFilterID = PhotoFilter.filters(in: category).first?.id ?? PhotoFilter.fallback.id
    }
}

struct PortraitEnhancement: Identifiable, Equatable {
    let id: String
    let title: String
    let subtitle: String
    let filterID: String

    static let all: [PortraitEnhancement] = [
        PortraitEnhancement(id: "natural", title: "自然", subtitle: "保留现场", filterID: "original"),
        PortraitEnhancement(id: "soft", title: "柔肤光泽", subtitle: "暖肤低反差", filterID: "skinGlow"),
        PortraitEnhancement(id: "bright", title: "亮肤", subtitle: "明亮清透", filterID: "brightAir"),
        PortraitEnhancement(id: "cream", title: "奶油", subtitle: "柔亮低饱和", filterID: "cream"),
        PortraitEnhancement(id: "warm", title: "暖肤", subtitle: "生活感胶片", filterID: "softPortrait")
    ]

    static let natural = all[0]

    static func enhancement(for id: String) -> PortraitEnhancement {
        all.first { $0.id == id } ?? natural
    }
}

enum ShootingAspectRatio: String, CaseIterable, Identifiable {
    case full
    case square
    case portrait
    case story

    var id: String { rawValue }

    var title: String {
        switch self {
        case .full: return "FULL"
        case .square: return "1:1"
        case .portrait: return "3:4"
        case .story: return "9:16"
        }
    }

    var numericRatio: CGFloat? {
        switch self {
        case .full: return nil
        case .square: return 1
        case .portrait: return 3.0 / 4.0
        case .story: return 9.0 / 16.0
        }
    }
}

enum HermesMode: String, CaseIterable, Identifiable {
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
    static let hermesMode = "hermesMode"
    static let automaticHermesInterval = "automaticHermesInterval"
    static let overlayIntensity = "overlayIntensity"
    static let apiKey = "hermesAPIKey"
    static let model = "hermesModel"
    static let apiBaseURL = "hermesAPIBaseURL"
    static let selectedFilterID = "selectedFilterID"
    static let selectedFilterCategory = "selectedFilterCategory"
    static let selectedPortraitEnhancementID = "selectedPortraitEnhancementID"
    static let selectedAspectRatio = "selectedAspectRatio"
    static let keychainService = "AICompositionCamera"
}

private enum LegacyKeys {
    static let apiKey = "openAIAPIKey"
    static let model = "openAIModel"
    static let apiBaseURL = "openAIAPIBaseURL"
}
