import SwiftUI
import UIKit

struct CameraView: View {
    @StateObject private var settings = SettingsStore()
    @StateObject private var camera = CameraSessionController()
    @StateObject private var gptAdvisor = GPTCompositionAdvisor()
    @State private var showingSettings = false
    @State private var lastAutomaticAnalysis = Date.distantPast
    @State private var lastAutomaticSceneSignature = ""
    @State private var automaticRequestDates: [Date] = []
    @State private var feedbackMessage: String?
    @State private var feedbackTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            if settings.selectedFilterID == PhotoFilter.fallback.id {
                CameraPreviewView(session: camera.session)
                    .ignoresSafeArea()
            } else {
                FilteredCameraPreviewView(image: camera.filteredPreviewImage ?? camera.latestImage)
                    .ignoresSafeArea()
            }

            OverlayView(result: camera.compositionResult, intensity: settings.overlayIntensity)
                .ignoresSafeArea()

            aspectRatioGuide

            VStack {
                topBar
                Spacer()
                feedbackToast
                featureModeStrip
                aiCoachPanel
                featurePanel
                controls
            }
            .padding()
        }
        .background(Color.black)
        .task {
            camera.setSelectedFilter(PhotoFilter.filter(for: settings.selectedFilterID))
            await camera.requestAccessAndStart()
        }
        .onChange(of: settings.selectedFilterID) { newValue in
            camera.setSelectedFilter(PhotoFilter.filter(for: newValue))
        }
        .onChange(of: gptAdvisor.recommendedFilterID) { newValue in
            guard let newValue, PhotoFilter.all.contains(where: { $0.id == newValue }) else { return }
            settings.selectedFilterID = newValue
        }
        .onDisappear {
            camera.stop()
        }
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            triggerAutomaticGPTIfNeeded()
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView(settings: settings)
        }
    }

    private var topBar: some View {
        HStack {
            statusPill
            Spacer()
            Button {
                buttonFeedback("打开设置")
                showingSettings = true
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(.black.opacity(0.35), in: Circle())
            }
            .buttonStyle(PressableButtonStyle())
        }
    }

    @ViewBuilder
    private var feedbackToast: some View {
        if let feedbackMessage {
            Text(feedbackMessage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(.black.opacity(0.58), in: Capsule())
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
        }
    }

    private var statusPill: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(camera.authorizationStatus == .authorized ? Color.green : Color.orange)
                .frame(width: 8, height: 8)
            Text(camera.statusText)
                .font(.caption.weight(.semibold))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.black.opacity(0.35), in: Capsule())
    }

    @ViewBuilder
    private var aspectRatioGuide: some View {
        if let ratio = settings.selectedAspectRatio.numericRatio {
            GeometryReader { geometry in
                let availableWidth = max(80, geometry.size.width - 32)
                let availableHeight = max(120, geometry.size.height - 220)
                let width = min(availableWidth, availableHeight * ratio)
                let height = width / max(ratio, 0.01)

                ZStack {
                    Rectangle()
                        .fill(.black.opacity(0.18))
                        .mask {
                            Rectangle()
                                .overlay {
                                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                                        .frame(width: width, height: height)
                                        .blendMode(.destinationOut)
                                }
                        }
                        .compositingGroup()

                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(.white.opacity(0.52), lineWidth: 1.4)
                        .frame(width: width, height: height)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .allowsHitTesting(false)
            .ignoresSafeArea()
        }
    }

    private var featureModeStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(CameraFeatureMode.allCases) { mode in
                    Button {
                        buttonFeedback("已切换到\(mode.title)")
                        settings.selectedCameraMode = mode
                    } label: {
                        Label(mode.title, systemImage: mode.systemImage)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(settings.selectedCameraMode == mode ? .black : .white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 9)
                            .background(modeBackground(mode), in: Capsule())
                    }
                    .buttonStyle(PressableButtonStyle())
                }
            }
            .padding(.horizontal, 2)
        }
        .padding(.top, 10)
    }

    private var featurePanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: settings.selectedCameraMode.systemImage)
                Text(settings.selectedCameraMode.panelTitle)
                    .font(.subheadline.weight(.bold))
                Spacer()
                Text(camera.selectedFilter.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.72))
            }

            Text(settings.selectedCameraMode.summary)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.78))

            switch settings.selectedCameraMode {
            case .photo:
                photoQuickPanel
            case .aiComposition:
                aiCompositionPanel
            case .portrait:
                portraitPanel
            case .beauty:
                beautyPanel
            case .filters:
                categorizedFilterPanel
            case .background:
                backgroundPanel
            case .pose:
                posePanel
            }
        }
        .foregroundStyle(.white)
        .padding(14)
        .background(.black.opacity(0.42), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var photoQuickPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            aspectRatioStrip
            filterStrip(filters: PhotoFilter.spotlight)
        }
    }

    private var aiCoachPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: aiCoachIcon)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.black)
                    .frame(width: 38, height: 38)
                    .background(.white.opacity(0.94), in: Circle())

                VStack(alignment: .leading, spacing: 5) {
                    Text(aiCoachTitle)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white.opacity(0.7))
                    Text(aiCoachMessage)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.white)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 6)

                if gptAdvisor.isAnalyzing {
                    ProgressView()
                        .tint(.white)
                }
            }

            if let recommendedFilter {
                Button {
                    buttonFeedback("已切换到 AI 推荐滤镜")
                    settings.selectedFilterID = recommendedFilter.id
                } label: {
                    Label("\(recommendedFilterPrefix) \(recommendedFilter.title)\(filterReasonSuffix)", systemImage: "camera.filters")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.black)
                        .lineLimit(1)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(.white.opacity(0.92), in: Capsule())
                }
                .buttonStyle(PressableButtonStyle())
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var aiCompositionPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                coachMetric(title: "识别", value: subjectStateText)
                coachMetric(title: "稳定", value: camera.isFrameStable ? "可分析" : "移动中")
                coachMetric(title: "模式", value: settings.gptMode.allowsAutomatic ? "自动" : "手动")
            }

            HStack(spacing: 10) {
                Button {
                    triggerManualGPT()
                } label: {
                    Label("GPT 识别取景", systemImage: "sparkles")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(.white.opacity(0.92), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(PressableButtonStyle())

                Button {
                    toggleAIMode()
                } label: {
                    Image(systemName: settings.gptMode.allowsAutomatic ? "bolt.circle.fill" : "bolt.slash.circle")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 42, height: 38)
                        .background(.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(PressableButtonStyle())
            }
        }
    }

    private var portraitPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(portraitHint)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.86))
            portraitEnhancementStrip
        }
    }

    private var beautyPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("轻美颜只调整肤色、亮度和柔和度，不做瘦脸、大眼或身体变形。", systemImage: "checkmark.seal")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.86))
            portraitEnhancementStrip
        }
    }

    private var categorizedFilterPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            categoryStrip
            filterStrip(filters: PhotoFilter.filters(in: settings.selectedFilterCategory))
        }
    }

    private var backgroundPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(backgroundHint, systemImage: "person.crop.square")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.86))
            HStack(spacing: 10) {
                quickFilterButton(id: "softPortrait", title: "主体柔和", subtitle: "人像")
                quickFilterButton(id: "cream", title: "奶油背景", subtitle: "低饱和")
                quickFilterButton(id: "moodyDark", title: "暗调突出", subtitle: "质感")
            }
        }
    }

    private var posePanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(camera.compositionResult?.topSuggestion ?? "保持人物完整入镜，头顶和脚边留出呼吸空间。", systemImage: "viewfinder")
                .font(.caption.weight(.semibold))
            Label("姿态模式会优先展示人脸位置、身体裁切和主体偏移提示。", systemImage: "figure.stand")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.78))
        }
    }

    private var categoryStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(FilterCategory.displayOrder, id: \.rawValue) { category in
                    Button {
                        buttonFeedback("已选择\(category.title)分类")
                        settings.selectedFilterCategory = category
                    } label: {
                        Text(category.title)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(settings.selectedFilterCategory == category ? .black : .white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(categoryBackground(category), in: Capsule())
                    }
                    .buttonStyle(PressableButtonStyle())
                }
            }
        }
    }

    private var aspectRatioStrip: some View {
        HStack(spacing: 8) {
            ForEach(ShootingAspectRatio.allCases) { ratio in
                Button {
                    buttonFeedback("取景比例 \(ratio.title)")
                    settings.selectedAspectRatio = ratio
                } label: {
                    Text(ratio.title)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(settings.selectedAspectRatio == ratio ? .black : .white)
                        .frame(width: 54, height: 34)
                        .background(aspectRatioBackground(ratio), in: Capsule())
                }
                .buttonStyle(PressableButtonStyle())
            }
        }
    }

    private var portraitEnhancementStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(PortraitEnhancement.all) { enhancement in
                    Button {
                        buttonFeedback("已选择\(enhancement.title)")
                        settings.selectedPortraitEnhancementID = enhancement.id
                        settings.selectedFilterID = enhancement.filterID
                    } label: {
                        VStack(spacing: 4) {
                            Text(enhancement.title)
                                .font(.caption.weight(.bold))
                            Text(enhancement.subtitle)
                                .font(.caption2)
                                .lineLimit(1)
                        }
                        .foregroundStyle(settings.selectedPortraitEnhancementID == enhancement.id ? .black : .white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background(enhancementBackground(enhancement), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(PressableButtonStyle())
                }
            }
        }
    }

    private func filterStrip(filters: [PhotoFilter]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(filters) { filter in
                    filterButton(filter)
                }
            }
            .padding(.horizontal, 2)
        }
    }

    private func filterButton(_ filter: PhotoFilter) -> some View {
        Button {
            buttonFeedback("已选择\(filter.title)")
            settings.selectedFilterID = filter.id
        } label: {
            VStack(spacing: 4) {
                Text(filter.title)
                    .font(.caption.weight(.bold))
                Text(filter.subtitle)
                    .font(.caption2)
                    .lineLimit(1)
            }
            .foregroundStyle(settings.selectedFilterID == filter.id ? .black : .white)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(filterBackground(filter), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(PressableButtonStyle())
    }

    private func quickFilterButton(id: String, title: String, subtitle: String) -> some View {
        let filter = PhotoFilter.filter(for: id)
        return Button {
            buttonFeedback("已选择\(title)")
            settings.selectedFilterID = filter.id
        } label: {
            VStack(spacing: 4) {
                Text(title)
                    .font(.caption.weight(.bold))
                Text(subtitle)
                    .font(.caption2)
            }
            .foregroundStyle(settings.selectedFilterID == filter.id ? .black : .white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(filterBackground(filter), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(PressableButtonStyle())
    }

    private func coachMetric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white.opacity(0.56))
            Text(value)
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var controls: some View {
        HStack(spacing: 28) {
            Button {
                triggerManualGPT()
            } label: {
                VStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 24, weight: .bold))
                    Text("AI 看一下")
                        .font(.caption.weight(.semibold))
                }
                .foregroundStyle(.white)
                .frame(width: 84, height: 70)
                .background(.white.opacity(0.18), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
            .opacity(settings.gptMode.allowsManual ? 1 : 0.45)
            .buttonStyle(PressableButtonStyle())

            Button {
                buttonFeedback("正在拍照")
                camera.capturePhoto(aspectRatio: settings.selectedAspectRatio)
            } label: {
                Circle()
                    .strokeBorder(.white, lineWidth: 5)
                    .frame(width: 76, height: 76)
                    .overlay {
                        Circle()
                            .fill(.white.opacity(0.85))
                            .frame(width: 58, height: 58)
                    }
            }
            .buttonStyle(PressableButtonStyle(scale: 0.92))

            Button {
                toggleAIMode()
            } label: {
                VStack(spacing: 6) {
                    Image(systemName: settings.gptMode.allowsAutomatic ? "bolt.circle.fill" : "bolt.slash.circle")
                        .font(.system(size: 24, weight: .bold))
                    Text(settings.gptMode.allowsAutomatic ? "自动 AI" : "手动 AI")
                        .font(.caption.weight(.semibold))
                }
                .foregroundStyle(.white)
                .frame(width: 84, height: 70)
                .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
            .buttonStyle(PressableButtonStyle())
        }
        .padding(.top, 10)
    }

    private func triggerManualGPT() {
        guard settings.gptMode.allowsManual else {
            buttonFeedback("请先在设置中开启手动 AI")
            return
        }
        guard !gptAdvisor.isAnalyzing else {
            buttonFeedback("AI 正在分析中")
            return
        }
        guard !settings.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            buttonFeedback("请先填写 API Key")
            return
        }
        guard camera.latestImage != nil else {
            buttonFeedback("相机画面准备中")
            return
        }

        buttonFeedback("已开始 AI 分析")
        camera.photoStatusText = nil
        Task {
            await gptAdvisor.analyze(
                image: camera.latestImage,
                localResult: camera.compositionResult,
                settings: settings
            )
        }
    }

    private func toggleAIMode() {
        if settings.gptMode.allowsAutomatic {
            settings.gptMode = .manual
            buttonFeedback("已切换为手动 AI")
        } else {
            settings.gptMode = .manualAndAutomatic
            buttonFeedback("已开启自动 AI")
        }
    }

    private func triggerAutomaticGPTIfNeeded() {
        guard settings.gptMode.allowsAutomatic else { return }
        guard !gptAdvisor.isAnalyzing else { return }
        guard camera.isFrameStable else { return }
        guard camera.latestImage != nil else { return }
        guard Date().timeIntervalSince(lastAutomaticAnalysis) >= settings.automaticGPTInterval else { return }
        guard hasAutomaticGPTBudget() else { return }

        let signature = camera.compositionResult?.sceneSignature ?? "no-result"
        guard signature != lastAutomaticSceneSignature else { return }

        lastAutomaticAnalysis = Date()
        lastAutomaticSceneSignature = signature
        automaticRequestDates.append(Date())
        camera.photoStatusText = nil
        Task {
            await gptAdvisor.analyze(
                image: camera.latestImage,
                localResult: camera.compositionResult,
                settings: settings
            )
        }
    }

    private func hasAutomaticGPTBudget() -> Bool {
        let cutoff = Date().addingTimeInterval(-60)
        automaticRequestDates = automaticRequestDates.filter { $0 >= cutoff }
        return automaticRequestDates.count < 6
    }

    private var recommendedFilter: PhotoFilter? {
        guard let id = gptAdvisor.recommendedFilterID else { return nil }
        return PhotoFilter.all.first { $0.id == id }
    }

    private var aiCoachIcon: String {
        if gptAdvisor.isAnalyzing { return "eye" }
        if gptAdvisor.errorMessage != nil { return "exclamationmark.triangle" }
        if gptAdvisor.advice != nil { return "sparkles" }
        if camera.photoStatusText != nil { return "photo" }
        return "viewfinder"
    }

    private var aiCoachTitle: String {
        if gptAdvisor.isAnalyzing { return "GPT 正在识别取景" }
        if gptAdvisor.errorMessage != nil { return "AI 构图未就绪" }
        if gptAdvisor.advice != nil { return "GPT 构图建议" }
        if camera.photoStatusText != nil { return "拍摄结果" }
        return "实时构图提示"
    }

    private var aiCoachMessage: String {
        if gptAdvisor.isAnalyzing { return "保持手机稳定，正在判断主体、留白和角度。" }
        if let error = gptAdvisor.errorMessage { return error }
        if let advice = gptAdvisor.advice, !advice.isEmpty { return advice }
        if let photoStatus = camera.photoStatusText { return photoStatus }
        return camera.compositionResult?.topSuggestion ?? "对准主体后点击 GPT 识别取景。"
    }

    private var subjectStateText: String {
        switch camera.compositionResult?.primarySubject?.kind {
        case .face?: return "人脸"
        case .human?: return "人物"
        case .object?: return "主体"
        case nil: return "等待"
        }
    }

    private var filterReasonSuffix: String {
        guard let reason = gptAdvisor.filterReason, !reason.isEmpty else { return "" }
        return "：\(reason)"
    }

    private var recommendedFilterPrefix: String {
        guard let recommendedFilter else { return "推荐" }
        return settings.selectedFilterID == recommendedFilter.id ? "已套用" : "推荐"
    }

    private var portraitHint: String {
        guard let result = camera.compositionResult else { return "把脸放在画面上三分之一附近，保留少量头顶空间。" }
        if result.primarySubject?.kind == .face { return "检测到人脸，建议优先使用柔和肤色和低反差滤镜。" }
        if result.primarySubject?.kind == .human { return "检测到人物，注意身体边缘不要被裁切。" }
        return "未检测到明确人像，可以先对准人物再拍。"
    }

    private var backgroundHint: String {
        guard camera.compositionResult?.primarySubject != nil else { return "对准人物或主体后，可用人像滤镜先突出主体。" }
        return "已识别主体。当前版本用色彩和构图突出背景层次，真实抠图/换背景后续接入分割模型。"
    }

    private func filterBackground(_ filter: PhotoFilter) -> AnyShapeStyle {
        settings.selectedFilterID == filter.id ? AnyShapeStyle(.white.opacity(0.92)) : AnyShapeStyle(.black.opacity(0.35))
    }

    private func modeBackground(_ mode: CameraFeatureMode) -> AnyShapeStyle {
        settings.selectedCameraMode == mode ? AnyShapeStyle(.white.opacity(0.92)) : AnyShapeStyle(.white.opacity(0.12))
    }

    private func categoryBackground(_ category: FilterCategory) -> AnyShapeStyle {
        settings.selectedFilterCategory == category ? AnyShapeStyle(.white.opacity(0.92)) : AnyShapeStyle(.white.opacity(0.12))
    }

    private func enhancementBackground(_ enhancement: PortraitEnhancement) -> AnyShapeStyle {
        settings.selectedPortraitEnhancementID == enhancement.id ? AnyShapeStyle(.white.opacity(0.92)) : AnyShapeStyle(.black.opacity(0.35))
    }

    private func aspectRatioBackground(_ ratio: ShootingAspectRatio) -> AnyShapeStyle {
        settings.selectedAspectRatio == ratio ? AnyShapeStyle(.white.opacity(0.92)) : AnyShapeStyle(.white.opacity(0.12))
    }

    private func buttonFeedback(_ message: String) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(.easeOut(duration: 0.16)) {
            feedbackMessage = message
        }

        feedbackTask?.cancel()
        feedbackTask = Task {
            try? await Task.sleep(nanoseconds: 1_400_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation(.easeIn(duration: 0.18)) {
                    feedbackMessage = nil
                }
            }
        }
    }
}

private struct PressableButtonStyle: ButtonStyle {
    var scale: CGFloat = 0.96

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .opacity(configuration.isPressed ? 0.72 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
