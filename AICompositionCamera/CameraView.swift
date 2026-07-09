import SwiftUI
import UIKit

struct CameraView: View {
    @StateObject private var settings = SettingsStore()
    @StateObject private var camera = CameraSessionController()
    @StateObject private var hermesAdvisor = HermesCompositionAdvisor()
    @State private var showingSettings = false
    @State private var lastAutomaticAnalysis = Date.distantPast
    @State private var automaticRequestDates: [Date] = []
    @State private var automaticSceneSignature: String?
    @State private var automaticSceneStableSince = Date()
    @State private var lastAutomaticSceneSignature: String?
    @State private var feedbackMessage: String?
    @State private var feedbackTask: Task<Void, Never>?
    @State private var focusIndicatorPoint: CGPoint?
    @State private var focusIndicatorTask: Task<Void, Never>?
    @State private var lastAppliedHermesZoom: CGFloat?
    @State private var lastAppliedHermesZoomDate = Date.distantPast
    @State private var zoomBeforeHermes: CGFloat?
    @State private var filterBeforeHermesID: String?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 10) {
                cameraStage
                lowerChrome
            }
            .padding(.horizontal, 18)
            .padding(.top, 6)
            .padding(.bottom, 14)

            VStack {
                Spacer()
                feedbackToast
                    .padding(.bottom, 170)
            }
            .padding(.horizontal, 18)
        }
        .task {
            camera.setSelectedFilter(PhotoFilter.filter(for: settings.selectedFilterID))
            await camera.requestAccessAndStart()
        }
        .onChange(of: settings.selectedFilterID) { newValue in
            camera.setSelectedFilter(PhotoFilter.filter(for: newValue))
        }
        .onChange(of: hermesAdvisor.recommendedFilterID) { newValue in
            guard let newValue, PhotoFilter.all.contains(where: { $0.id == newValue }) else { return }
            rememberCameraStateBeforeHermesIfNeeded()
            settings.selectedFilterID = newValue
        }
        .onChange(of: hermesAdvisor.captureGuidance) { newValue in
            applyHermesZoomIfNeeded(newValue)
        }
        .onDisappear {
            camera.stop()
        }
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            triggerAutomaticHermesIfNeeded()
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView(settings: settings)
        }
    }

    private var topBar: some View {
        HStack {
            statusPill
            Spacer()
            Text("Hermes")
                .font(.caption.weight(.bold))
                .foregroundStyle(.white.opacity(0.72))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(.white.opacity(0.10), in: Capsule())
        }
    }

    private var cameraStage: some View {
        ZStack {
            cameraSurface

            OverlayView(result: camera.compositionResult, intensity: settings.overlayIntensity)

            stageAspectRatioGuide

            CaptureGuidanceOverlay(
                guidance: activeCaptureGuidance,
                imageAspectRatio: camera.compositionResult?.imageAspectRatio ?? 9.0 / 16.0,
                currentZoomFactor: camera.zoomFactor
            )

            focusIndicator

            VStack(spacing: 0) {
                stageTopOverlay
                Spacer()
                zoomStrip
                    .padding(.bottom, 18)
            }
            .padding(16)
        }
        .frame(maxWidth: .infinity)
        .frame(height: min(UIScreen.main.bounds.height * 0.66, 640))
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(.white.opacity(0.12), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.45), radius: 18, x: 0, y: 10)
    }

    @ViewBuilder
    private var cameraSurface: some View {
        if settings.selectedFilterID == PhotoFilter.fallback.id {
            CameraPreviewView(
                session: camera.session,
                mirrored: camera.cameraPosition == .front
            ) { devicePoint, layerPoint in
                handleFocusTap(devicePoint: devicePoint, layerPoint: layerPoint)
            }
        } else {
            FilteredCameraPreviewView(
                image: camera.filteredPreviewImage ?? camera.latestImage,
                mirrored: camera.cameraPosition == .front
            ) { devicePoint, layerPoint in
                handleFocusTap(devicePoint: devicePoint, layerPoint: layerPoint)
            }
        }
    }

    private var stageTopOverlay: some View {
        HStack(alignment: .top) {
            Button {
                settings.overlayIntensity = settings.overlayIntensity == .minimal ? .normal : .minimal
                buttonFeedback(settings.overlayIntensity == .minimal ? "已隐藏辅助线" : "已显示辅助线")
            } label: {
                Image(systemName: settings.overlayIntensity == .minimal ? "eye.slash" : "grid")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 42, height: 42)
                    .background(.black.opacity(0.34), in: Circle())
            }
            .buttonStyle(PressableButtonStyle())

            Spacer()

            Text(stageHintText)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .frame(maxWidth: 180)
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .background(.black.opacity(0.42), in: Capsule())
                .overlay {
                    Capsule()
                        .stroke(.white.opacity(0.22), lineWidth: 1)
                }

            Spacer()

            HStack(spacing: 8) {
                Button {
                    clearHermesSession(restoreCamera: false, showFeedback: false)
                    camera.switchCamera()
                    buttonFeedback(camera.cameraPosition == .back ? "切换前置相机" : "切换后置相机")
                } label: {
                    Image(systemName: "arrow.triangle.2.circlepath.camera")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 42, height: 42)
                        .background(.black.opacity(0.34), in: Circle())
                }
                .buttonStyle(PressableButtonStyle())

                Button {
                    buttonFeedback("打开设置")
                    showingSettings = true
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 42, height: 42)
                        .background(.black.opacity(0.34), in: Circle())
                }
                .buttonStyle(PressableButtonStyle())
            }
        }
    }

    @ViewBuilder
    private var focusIndicator: some View {
        if let focusIndicatorPoint {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(.yellow.opacity(0.92), lineWidth: 2)
                .frame(width: 72, height: 72)
                .position(focusIndicatorPoint)
                .transition(.opacity.combined(with: .scale(scale: 0.82)))
                .allowsHitTesting(false)
        }
    }

    private var zoomStrip: some View {
        HStack(spacing: 0) {
            ForEach([CGFloat(0.5), 1, 2, 4, 8], id: \.self) { zoom in
                let isSelected = abs(camera.zoomFactor - zoom) < 0.08
                let isSupported = isZoomSupported(zoom)

                Button {
                    guard isSupported else {
                        buttonFeedback("当前镜头不支持 \(zoomLabel(zoom))x")
                        return
                    }
                    camera.setZoomFactor(zoom)
                    buttonFeedback("已切换到 \(zoomLabel(zoom))x")
                } label: {
                    Text("\(zoomLabel(zoom))x")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(isSelected ? .black : .white.opacity(isSupported ? 1 : 0.38))
                        .frame(width: 54, height: 40)
                        .background {
                            if isSelected {
                                Circle().fill(.white.opacity(0.94))
                            }
                        }
                }
                .buttonStyle(PressableButtonStyle(scale: 0.9))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.black.opacity(0.30), in: Capsule())
    }

    private var lowerChrome: some View {
        VStack(spacing: 8) {
            shootingModeBar
            if settings.selectedCameraMode == .aiComposition {
                compactCoachBar
            } else {
                featurePanel
            }
            controls
        }
    }

    private var shootingModeBar: some View {
        HStack(spacing: 10) {
            featureModeStrip
            aspectRatioButton
        }
    }

    private var modeBar: some View {
        HStack {
            Spacer()

            aspectRatioButton

            Spacer()
        }
        .padding(.horizontal, 34)
    }

    private var aspectRatioButton: some View {
            Button {
                cycleAspectRatio()
            } label: {
                VStack(spacing: 2) {
                    Image(systemName: "rectangle.portrait")
                        .font(.system(size: 22, weight: .semibold))
                    Text(settings.selectedAspectRatio.title)
                        .font(.caption2.weight(.bold))
                }
                .foregroundStyle(.white)
                .frame(width: 48, height: 44)
            }
            .buttonStyle(PressableButtonStyle())
    }

    private var compactCoachBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Image(systemName: aiCoachIcon)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.black)
                    .frame(width: 34, height: 34)
                    .background(.white.opacity(0.94), in: Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(aiCoachTitle)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white.opacity(0.58))
                    Text(aiCoachMessage)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                }

                Spacer(minLength: 8)

                if hermesAdvisor.isAnalyzing {
                    ProgressView()
                        .tint(.white)
                } else if hasHermesResult {
                    Button {
                        clearHermesSession()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(.white.opacity(0.92))
                            .frame(width: 34, height: 34)
                    }
                    .buttonStyle(PressableButtonStyle(scale: 0.9))
                    .accessibilityLabel("退出 Hermes 识别")
                }
            }

            HStack(spacing: 8) {
                directorChip(title: "主体", value: directorSubjectText, systemImage: "viewfinder")
                directorChip(title: "动作", value: directorMoveText, systemImage: "location.fill")
                directorChip(title: "倍率", value: directorZoomText, systemImage: "scope")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func directorChip(title: String, value: String, systemImage: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white.opacity(0.66))
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white.opacity(0.48))
                Text(value)
                    .font(.caption.weight(.heavy))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(.black.opacity(0.24), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
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

    @ViewBuilder
    private var stageAspectRatioGuide: some View {
        if let ratio = settings.selectedAspectRatio.numericRatio {
            GeometryReader { geometry in
                let availableWidth = max(80, geometry.size.width - 20)
                let availableHeight = max(120, geometry.size.height - 20)
                let width = min(availableWidth, availableHeight * ratio)
                let height = width / max(ratio, 0.01)

                ZStack {
                    Rectangle()
                        .fill(.black.opacity(0.16))
                        .mask {
                            Rectangle()
                                .overlay {
                                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                                        .frame(width: width, height: height)
                                        .blendMode(.destinationOut)
                                }
                        }
                        .compositingGroup()

                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(.white.opacity(0.48), lineWidth: 1.2)
                        .frame(width: width, height: height)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .allowsHitTesting(false)
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
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(settings.selectedCameraMode == mode ? .black : .white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(modeBackground(mode), in: Capsule())
                    }
                    .buttonStyle(PressableButtonStyle())
                }
            }
            .padding(.horizontal, 2)
        }
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

                if hermesAdvisor.isAnalyzing {
                    ProgressView()
                        .tint(.white)
                } else if hasHermesResult {
                    Button {
                        clearHermesSession()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundStyle(.white.opacity(0.92))
                            .frame(width: 34, height: 34)
                    }
                    .buttonStyle(PressableButtonStyle(scale: 0.9))
                    .accessibilityLabel("退出 Hermes 识别")
                }
            }

            if let recommendedFilter {
                Button {
                    buttonFeedback("已切换到 Hermes 推荐滤镜")
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
                coachMetric(title: "模式", value: settings.hermesMode.allowsAutomatic ? "自动" : "手动")
            }

            HStack(spacing: 10) {
                Button {
                    triggerManualHermes()
                } label: {
                    Label(hasHermesResult ? "重新识别" : "Hermes 识别", systemImage: "sparkles")
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
                    Image(systemName: settings.hermesMode.allowsAutomatic ? "bolt.circle.fill" : "bolt.slash.circle")
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
        HStack(spacing: 26) {
            Button {
                if hasHermesResult {
                    clearHermesSession()
                } else {
                    triggerManualHermes()
                }
            } label: {
                VStack(spacing: 6) {
                    Image(systemName: hasHermesResult ? "xmark.circle.fill" : "sparkles")
                        .font(.system(size: 24, weight: .bold))
                    Text(hasHermesResult ? "退出" : "识别")
                        .font(.caption2.weight(.semibold))
                }
                .foregroundStyle(.white)
                .frame(width: 78, height: 60)
                .background(.white.opacity(0.18), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .opacity(settings.hermesMode.allowsManual ? 1 : 0.45)
            .buttonStyle(PressableButtonStyle())

            Button {
                buttonFeedback(camera.isCapturingPhoto ? "正在保存上一张照片" : (isCaptureReady ? "构图就绪，正在拍照" : "正在拍照"))
                camera.capturePhoto(aspectRatio: settings.selectedAspectRatio)
            } label: {
                Circle()
                    .strokeBorder(shutterAccentColor, lineWidth: 5)
                    .frame(width: 70, height: 70)
                    .overlay {
                        Circle()
                            .fill(shutterFillColor)
                            .frame(width: 54, height: 54)
                    }
                    .overlay {
                        if camera.isCapturingPhoto {
                            ProgressView()
                                .tint(.black)
                        } else if isCaptureReady {
                            Image(systemName: "checkmark")
                                .font(.system(size: 24, weight: .heavy))
                                .foregroundStyle(.black)
                        }
                    }
            }
            .buttonStyle(PressableButtonStyle(scale: 0.92))

            Button {
                toggleAIMode()
            } label: {
                VStack(spacing: 6) {
                    Image(systemName: settings.hermesMode.allowsAutomatic ? "bolt.circle.fill" : "bolt.slash.circle")
                        .font(.system(size: 24, weight: .bold))
                    Text(settings.hermesMode.allowsAutomatic ? "自动 Hermes" : "手动 Hermes")
                        .font(.caption2.weight(.semibold))
                }
                .foregroundStyle(.white)
                .frame(width: 78, height: 60)
                .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(PressableButtonStyle())
        }
        .padding(.top, 10)
    }

    private func triggerManualHermes() {
        guard settings.hermesMode.allowsManual else {
            buttonFeedback("请先开启手动 Hermes")
            return
        }
        guard !hermesAdvisor.isAnalyzing else {
            buttonFeedback("Hermes 正在取景")
            return
        }
        guard settings.usesHermesPublicGateway || !settings.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            buttonFeedback("私有网关需要 API Key")
            return
        }
        guard camera.latestImage != nil else {
            buttonFeedback("相机画面准备中")
            return
        }

        buttonFeedback("Hermes 正在指导取景")
        beginHermesSession()
        camera.photoStatusText = nil
        Task {
            await hermesAdvisor.analyze(
                image: camera.latestImage,
                localResult: camera.compositionResult,
                settings: settings
            )
        }
    }

    private func toggleAIMode() {
        if settings.hermesMode.allowsAutomatic {
            settings.hermesMode = .manual
            buttonFeedback("已切换为手动 Hermes")
        } else {
            settings.hermesMode = .manualAndAutomatic
            buttonFeedback("已开启自动 Hermes")
        }
    }

    private func triggerAutomaticHermesIfNeeded() {
        guard settings.hermesMode.allowsAutomatic else { return }
        guard !hermesAdvisor.isAnalyzing else { return }
        guard settings.usesHermesPublicGateway || !settings.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        guard camera.latestImage != nil else { return }
        let now = Date()
        guard camera.isFrameStable else {
            resetAutomaticSceneTracking(now: now)
            return
        }
        guard let signature = updateAutomaticSceneTracking(now: now) else { return }
        let sceneChangedAfterResult = hasHermesResult && signature != lastAutomaticSceneSignature
        let minimumInterval = sceneChangedAfterResult ? min(3, settings.automaticHermesInterval) : settings.automaticHermesInterval
        guard now.timeIntervalSince(automaticSceneStableSince) >= settings.automaticHermesInterval else { return }
        guard now.timeIntervalSince(lastAutomaticAnalysis) >= minimumInterval else { return }
        guard signature != lastAutomaticSceneSignature || now.timeIntervalSince(lastAutomaticAnalysis) >= 30 else { return }
        guard hasAutomaticHermesBudget() else { return }

        lastAutomaticAnalysis = now
        lastAutomaticSceneSignature = signature
        automaticRequestDates.append(now)
        beginHermesSession()
        camera.photoStatusText = nil
        Task {
            await hermesAdvisor.analyze(
                image: camera.latestImage,
                localResult: camera.compositionResult,
                settings: settings
            )
        }
    }

    private func updateAutomaticSceneTracking(now: Date) -> String? {
        guard let signature = currentAutomaticSceneSignature else {
            resetAutomaticSceneTracking(now: now)
            return nil
        }

        if automaticSceneSignature != signature {
            automaticSceneSignature = signature
            automaticSceneStableSince = now
        }

        return signature
    }

    private func resetAutomaticSceneTracking(now: Date = Date()) {
        automaticSceneSignature = nil
        automaticSceneStableSince = now
    }

    private var currentAutomaticSceneSignature: String? {
        guard camera.latestImage != nil else { return nil }
        if let result = camera.compositionResult {
            return result.sceneSignature
        }
        return "whole-frame"
    }

    private func hasAutomaticHermesBudget() -> Bool {
        let cutoff = Date().addingTimeInterval(-60)
        automaticRequestDates = automaticRequestDates.filter { $0 >= cutoff }
        return automaticRequestDates.count < 6
    }

    private var recommendedFilter: PhotoFilter? {
        guard let id = hermesAdvisor.recommendedFilterID else { return nil }
        return PhotoFilter.all.first { $0.id == id }
    }

    private var directorSubjectText: String {
        if hermesAdvisor.isAnalyzing { return "识别中" }
        if let subject = hermesAdvisor.recognizedSubject, !subject.isEmpty { return subject }
        if camera.compositionResult?.primarySubject != nil { return subjectStateText }
        return "待识别"
    }

    private var directorMoveText: String {
        if hermesAdvisor.isAnalyzing { return "分析中" }
        if hermesAdvisor.errorMessage != nil { return "本地指导" }
        if !hasHermesResult, settings.hermesMode.allowsAutomatic {
            return automaticReadinessText
        }
        guard let guidance = activeCaptureGuidance else { return "等待主体" }
        if let direction = guidance.direction {
            return guidance.message.isEmpty ? direction.title : guidance.message
        }
        if guidance.zoomFactor != nil {
            return guidance.message.isEmpty ? "调整倍率" : guidance.message
        }
        return "继续取景"
    }

    private var directorZoomText: String {
        if let zoom = normalizedGuidance(hermesAdvisor.captureGuidance)?.zoomFactor {
            return "\(zoomLabel(zoom))x"
        }
        if let zoom = normalizedGuidance(camera.compositionResult?.liveGuidance)?.zoomFactor {
            return "\(zoomLabel(zoom))x"
        }
        return "\(zoomLabel(camera.zoomFactor))x"
    }

    private var automaticReadinessText: String {
        guard camera.latestImage != nil else { return "相机准备中" }
        guard camera.isFrameStable else { return "稳住画面" }
        let elapsed = Date().timeIntervalSince(automaticSceneStableSince)
        let remaining = max(0, settings.automaticHermesInterval - elapsed)
        if remaining > 0.5 {
            return "\(Int(ceil(remaining)))秒后识别"
        }
        return "即将识别"
    }

    private var hasHermesResult: Bool {
        hermesAdvisor.advice != nil ||
        hermesAdvisor.captureGuidance != nil ||
        hermesAdvisor.recognizedSubject != nil ||
        hermesAdvisor.recommendedFilterID != nil ||
        hermesAdvisor.filterReason != nil ||
        hermesAdvisor.errorMessage != nil
    }

    private var activeCaptureGuidance: CaptureGuidance? {
        if let hermesGuidance = hermesAdvisor.captureGuidance {
            return normalizedGuidance(hermesGuidance)
        }

        let localGuidance = normalizedGuidance(camera.compositionResult?.liveGuidance)
        if localGuidance?.direction == .hold, hermesAdvisor.advice != nil {
            return nil
        }

        return localGuidance
    }

    private var stageHintText: String {
        if hermesAdvisor.isAnalyzing { return "正在识别取景" }
        if let guidance = normalizedGuidance(hermesAdvisor.captureGuidance) {
            if let zoom = guidance.zoomFactor {
                return "\(guidance.message) \(zoomLabel(zoom))x"
            }
            return guidance.message
        }
        if let advice = hermesAdvisor.advice, !advice.isEmpty { return advice }
        if settings.hermesMode.allowsAutomatic, !hasHermesResult {
            return automaticReadinessText
        }
        if let guidance = activeCaptureGuidance {
            if let zoom = guidance.zoomFactor {
                return "\(guidance.message) \(zoomLabel(zoom))x"
            }
            return guidance.message
        }
        if let suggestion = camera.compositionResult?.topSuggestion { return suggestion }
        return "对准主体后按指导"
    }

    private var aiCoachIcon: String {
        if hermesAdvisor.isAnalyzing { return "eye" }
        if hermesAdvisor.errorMessage != nil { return "exclamationmark.triangle" }
        if hermesAdvisor.advice != nil { return "sparkles" }
        if camera.photoStatusText != nil { return "photo" }
        return "sparkles"
    }

    private var aiCoachTitle: String {
        if hermesAdvisor.isAnalyzing { return "Hermes 正在识别取景" }
        if hermesAdvisor.errorMessage != nil { return "Hermes 暂不可用" }
        if let subject = hermesAdvisor.recognizedSubject, !subject.isEmpty { return "Hermes 识别：\(subject)" }
        if hermesAdvisor.advice != nil { return "Hermes 取景建议" }
        if camera.photoStatusText != nil { return "拍摄结果" }
        return "Hermes 待识别"
    }

    private var aiCoachMessage: String {
        if hermesAdvisor.isAnalyzing { return "保持手机稳定，正在判断主体、留白和角度。" }
        if let error = hermesAdvisor.errorMessage { return error }
        if let guidance = normalizedGuidance(hermesAdvisor.captureGuidance) {
            if let zoom = guidance.zoomFactor {
                return "\(guidance.message)，切到 \(zoomLabel(zoom))x 取景。"
            }
            return guidance.message
        }
        if let advice = hermesAdvisor.advice, !advice.isEmpty { return advice }
        if let guidance = activeCaptureGuidance {
            if let zoom = guidance.zoomFactor {
                return "\(guidance.message)，切到 \(zoomLabel(zoom))x 取景。"
            }
            return guidance.message
        }
        if let photoStatus = camera.photoStatusText { return photoStatus }
        if settings.hermesMode.allowsAutomatic {
            return "稳住画面 5 秒，Hermes 会自动识别并接管取景。"
        }
        if let guidance = activeCaptureGuidance, guidance.message != "可以拍" {
            return "本地预判：\(guidance.message)。点识别让 Hermes 接管。"
        }
        return "点识别，让 Hermes 判断主体、位置和倍率。"
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
        guard let reason = hermesAdvisor.filterReason, !reason.isEmpty else { return "" }
        return "：\(reason)"
    }

    private var recommendedFilterPrefix: String {
        guard let recommendedFilter else { return "推荐" }
        return settings.selectedFilterID == recommendedFilter.id ? "已套用" : "推荐"
    }

    private var isCaptureReady: Bool {
        activeCaptureGuidance?.direction == .hold && camera.isFrameStable && !hermesAdvisor.isAnalyzing && !camera.isCapturingPhoto
    }

    private var shutterAccentColor: Color {
        if camera.isCapturingPhoto { return .white.opacity(0.52) }
        if isCaptureReady { return .green.opacity(0.95) }
        return .white
    }

    private var shutterFillColor: Color {
        if camera.isCapturingPhoto { return .white.opacity(0.72) }
        if isCaptureReady { return .green.opacity(0.9) }
        return .white.opacity(0.85)
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

    private func isZoomSupported(_ zoom: CGFloat) -> Bool {
        zoom >= camera.minZoomFactor - 0.02 && zoom <= camera.maxZoomFactor + 0.02
    }

    private func normalizedGuidance(_ guidance: CaptureGuidance?) -> CaptureGuidance? {
        guard var guidance else { return nil }
        guard let zoom = guidance.zoomFactor else { return guidance }

        if isZoomSupported(zoom) {
            return guidance
        }

        if zoom < camera.minZoomFactor {
            guidance.zoomFactor = nil
            if guidance.direction == nil || guidance.direction == .closer {
                guidance.direction = .farther
                guidance.message = "后退一点"
            }
            return guidance
        }

        if camera.maxZoomFactor <= 1.05 {
            guidance.zoomFactor = nil
            if guidance.direction == nil || guidance.direction == .hold {
                guidance.direction = .closer
            }
            guidance.message = "靠近主体"
            return guidance
        }

        guidance.zoomFactor = camera.maxZoomFactor
        guidance.message = "切到 \(zoomLabel(camera.maxZoomFactor))x"
        return guidance
    }

    private func applyHermesZoomIfNeeded(_ guidance: CaptureGuidance?) {
        guard let guidance = normalizedGuidance(guidance), let zoom = guidance.zoomFactor else { return }
        guard isZoomSupported(zoom) else { return }
        guard abs(camera.zoomFactor - zoom) >= 0.08 else { return }

        let recentlyAppliedSameZoom = lastAppliedHermesZoom.map {
            abs($0 - zoom) < 0.08 && Date().timeIntervalSince(lastAppliedHermesZoomDate) < 8
        } ?? false
        guard !recentlyAppliedSameZoom else { return }

        rememberCameraStateBeforeHermesIfNeeded()
        lastAppliedHermesZoom = zoom
        lastAppliedHermesZoomDate = Date()
        camera.setZoomFactor(zoom)
        buttonFeedback("Hermes 已切到 \(zoomLabel(zoom))x")
    }

    private func beginHermesSession() {
        zoomBeforeHermes = camera.zoomFactor
        filterBeforeHermesID = settings.selectedFilterID
        resetAutomaticSceneTracking()
        resetHermesZoomMemory()
        hermesAdvisor.reset()
    }

    private func rememberCameraStateBeforeHermesIfNeeded() {
        if zoomBeforeHermes == nil {
            zoomBeforeHermes = camera.zoomFactor
        }
        if filterBeforeHermesID == nil {
            filterBeforeHermesID = settings.selectedFilterID
        }
    }

    private func clearHermesSession(restoreCamera: Bool = true, showFeedback: Bool = true) {
        let zoomToRestore = zoomBeforeHermes
        let filterToRestore = filterBeforeHermesID

        hermesAdvisor.reset()
        resetHermesZoomMemory()
        zoomBeforeHermes = nil
        filterBeforeHermesID = nil
        lastAutomaticAnalysis = Date()
        lastAutomaticSceneSignature = currentAutomaticSceneSignature
        resetAutomaticSceneTracking()

        if restoreCamera {
            if let filterToRestore, PhotoFilter.all.contains(where: { $0.id == filterToRestore }) {
                settings.selectedFilterID = filterToRestore
            }
            if let zoomToRestore, isZoomSupported(zoomToRestore) {
                camera.setZoomFactor(zoomToRestore)
            }
        }

        if showFeedback {
            buttonFeedback(restoreCamera ? "已退出识别并恢复取景" : "已退出 Hermes 识别")
        }
    }

    private func resetHermesZoomMemory() {
        lastAppliedHermesZoom = nil
        lastAppliedHermesZoomDate = Date.distantPast
    }

    private func zoomLabel(_ value: CGFloat) -> String {
        let rounded = (value * 10).rounded() / 10
        if rounded.rounded() == rounded {
            return String(Int(rounded))
        }
        return String(format: "%.1f", Double(rounded))
    }

    private func cycleAspectRatio() {
        let ratios = ShootingAspectRatio.allCases
        guard let index = ratios.firstIndex(of: settings.selectedAspectRatio) else {
            settings.selectedAspectRatio = .full
            return
        }
        settings.selectedAspectRatio = ratios[(index + 1) % ratios.count]
        buttonFeedback("取景比例 \(settings.selectedAspectRatio.title)")
    }

    private func handleFocusTap(devicePoint: CGPoint, layerPoint: CGPoint) {
        camera.focusAndExpose(at: devicePoint)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(.spring(response: 0.22, dampingFraction: 0.74)) {
            focusIndicatorPoint = layerPoint
        }

        focusIndicatorTask?.cancel()
        focusIndicatorTask = Task {
            try? await Task.sleep(nanoseconds: 900_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation(.easeOut(duration: 0.2)) {
                    focusIndicatorPoint = nil
                }
            }
        }
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
