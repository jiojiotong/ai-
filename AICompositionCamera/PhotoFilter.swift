import Foundation

struct PhotoFilter: Identifiable, Equatable {
    let id: String
    let title: String
    let subtitle: String
    let category: FilterCategory
    let aiDescription: String

    static let all: [PhotoFilter] = [
        PhotoFilter(
            id: "original",
            title: "原图",
            subtitle: "自然还原",
            category: .neutral,
            aiDescription: "不改变画面，适合色彩和光线已经自然的场景。"
        ),
        PhotoFilter(
            id: "vivid",
            title: "鲜明",
            subtitle: "高饱和高对比",
            category: .neutral,
            aiDescription: "增强饱和度和对比度，适合日常、美食、色彩丰富的画面。"
        ),
        PhotoFilter(
            id: "warmFilm",
            title: "暖调胶片",
            subtitle: "温暖柔和",
            category: .portrait,
            aiDescription: "偏暖、柔和高光，适合人像、夕阳、生活感照片。"
        ),
        PhotoFilter(
            id: "japaneseSoft",
            title: "日系淡彩",
            subtitle: "低对比清透",
            category: .portrait,
            aiDescription: "低对比、浅色、清透，适合明亮环境、人像、静物。"
        ),
        PhotoFilter(
            id: "coolStreet",
            title: "冷调街拍",
            subtitle: "冷影硬朗",
            category: .street,
            aiDescription: "冷色阴影和较强对比，适合街景、建筑、城市夜色。"
        ),
        PhotoFilter(
            id: "monoClassic",
            title: "经典黑白",
            subtitle: "去色重结构",
            category: .blackAndWhite,
            aiDescription: "黑白中等对比，适合线条强、光影明显、情绪感强的画面。"
        ),
        PhotoFilter(
            id: "retro",
            title: "复古",
            subtitle: "褪色暖棕",
            category: .creative,
            aiDescription: "轻微褪色和暖棕色调，适合旧物、咖啡馆、怀旧场景。"
        ),
        PhotoFilter(
            id: "cyber",
            title: "赛博霓虹",
            subtitle: "蓝紫高反差",
            category: .night,
            aiDescription: "蓝紫色倾向和高反差，适合夜景、霓虹、科技感画面。"
        ),
        PhotoFilter(
            id: "softPortrait",
            title: "柔和人像",
            subtitle: "暖肤低反差",
            category: .portrait,
            aiDescription: "低反差、偏暖、肤色友好，适合近景人像和自拍。"
        ),
        PhotoFilter(
            id: "landscapePop",
            title: "风景增强",
            subtitle: "蓝绿更通透",
            category: .landscape,
            aiDescription: "增强蓝色绿色和局部对比，适合天空、植物、远景风光。"
        ),
        PhotoFilter(
            id: "clarendon",
            title: "清澈蓝调",
            subtitle: "蓝色覆层",
            category: .creative,
            aiDescription: "参考 Clarendon 风格，蓝色覆层、较高饱和和轻微提亮，适合天空、街景和清爽照片。"
        ),
        PhotoFilter(
            id: "nashville",
            title: "纳什暖调",
            subtitle: "暖粉复古",
            category: .creative,
            aiDescription: "参考 Nashville 风格，暖粉与蓝色混合、复古感强，适合人像、咖啡馆和生活照片。"
        ),
        PhotoFilter(
            id: "tealOrange",
            title: "电影青橙",
            subtitle: "青影橙肤",
            category: .creative,
            aiDescription: "电影感青橙色，适合人物、城市、逆光和有明确冷暖对比的画面。"
        ),
        PhotoFilter(
            id: "kodakGold",
            title: "柯达金",
            subtitle: "金黄胶片",
            category: .creative,
            aiDescription: "温暖金黄色胶片感，适合阳光、街拍、旅行和生活记录。"
        ),
        PhotoFilter(
            id: "fujiGreen",
            title: "富士绿",
            subtitle: "青绿通透",
            category: .landscape,
            aiDescription: "青绿色偏移和通透感，适合植物、街景、阴天和日系风格。"
        ),
        PhotoFilter(
            id: "cream",
            title: "奶油",
            subtitle: "柔亮低饱和",
            category: .portrait,
            aiDescription: "柔亮、低饱和、低对比，适合人像、咖啡、室内和温柔氛围。"
        ),
        PhotoFilter(
            id: "foodie",
            title: "美食",
            subtitle: "暖亮诱人",
            category: .neutral,
            aiDescription: "提高暖色、亮度和饱和，适合食物、饮品、餐桌静物。"
        ),
        PhotoFilter(
            id: "nightCity",
            title: "夜景城市",
            subtitle: "压暗提亮灯光",
            category: .night,
            aiDescription: "压暗阴影、增强灯光和色彩，适合夜景、路灯、城市街头。"
        ),
        PhotoFilter(
            id: "moodyDark",
            title: "暗调质感",
            subtitle: "低曝光高对比",
            category: .creative,
            aiDescription: "暗调、高对比、情绪感强，适合阴影、室内、低光和质感照片。"
        ),
        PhotoFilter(
            id: "brightAir",
            title: "空气感",
            subtitle: "明亮清透",
            category: .portrait,
            aiDescription: "明亮、清透、轻微降对比，适合窗边光、人像、天空和干净场景。"
        ),
        PhotoFilter(
            id: "noirHigh",
            title: "高反差黑白",
            subtitle: "强光影",
            category: .blackAndWhite,
            aiDescription: "高反差黑白，适合强线条、强光影、建筑和街头纪实。"
        ),
        PhotoFilter(
            id: "instant",
            title: "拍立得",
            subtitle: "即时成片",
            category: .creative,
            aiDescription: "类似拍立得的复古即时感，适合日常、人像、聚会和随手拍。"
        ),
        PhotoFilter(
            id: "chrome",
            title: "反转片",
            subtitle: "浓郁通透",
            category: .landscape,
            aiDescription: "反转片风格，色彩浓郁、对比清晰，适合风景、建筑和旅行照。"
        ),
        PhotoFilter(
            id: "fadeMatte",
            title: "褪色哑光",
            subtitle: "低黑位",
            category: .creative,
            aiDescription: "褪色、哑光、低黑位，适合文艺、人像、静物和复古场景。"
        ),
        PhotoFilter(
            id: "summer",
            title: "夏日",
            subtitle: "明快高饱和",
            category: .landscape,
            aiDescription: "明快、高饱和、偏暖，适合海边、蓝天、户外和阳光场景。"
        ),
        PhotoFilter(
            id: "autumn",
            title: "秋日",
            subtitle: "橙棕暖调",
            category: .landscape,
            aiDescription: "橙棕暖调，适合落叶、傍晚、咖啡馆和温暖生活场景。"
        ),
        PhotoFilter(
            id: "skinGlow",
            title: "肤色光泽",
            subtitle: "暖肤提亮",
            category: .portrait,
            aiDescription: "轻微提亮、暖肤、低对比，适合近景人像和自拍，不做磨皮变形。"
        )
    ]

    static let fallback = all[0]

    static func filter(for id: String) -> PhotoFilter {
        all.first { $0.id == id } ?? fallback
    }

    static var gptCatalog: String {
        all.map { "\($0.id): \($0.title)，\($0.aiDescription)" }.joined(separator: "\n")
    }
}

enum FilterCategory: String {
    case neutral
    case portrait
    case street
    case landscape
    case night
    case blackAndWhite
    case creative
}
