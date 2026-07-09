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

            cameraStage

            cameraChrome

            VStack {
                Spacer()
                feedbackToast
                    .padding(.bottom, 154)
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

            cameraReadinessOverlay
        }
        .ignoresSafeArea()
    }

    private var cameraChrome: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                stageTopOverlay

                Spacer()

                zoomStrip
                    .padding(.bottom, 12)

                compactCoachBar
                    .padding(.bottom, 12)

                controls
            }
            .padding(.horizontal, 16)
            .padding(.top, max(geometry.safeAreaInsets.top, 14))
            .padding(.bottom, max(geometry.safeAreaInsets.bottom, 12) + 6)
        }
        .ignoresSafeArea(edges: .bottom)
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

    private var compactCoachBar: some View {
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
                    .minimumScaleFactor(0.72)
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
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.black.opacity(0.50), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(.white.opacity(0.12), lineWidth: 1)
        }
    }

    @ViewBuilder
    private var cameraReadinessOverlay: some View {
        if camera.authorizationStatus != .authorized || camera.latestImage == nil {
            VStack(spacing: 14) {
                Image(systemName: camera.authorizationStatus == .authorized ? "camera.viewfinder" : "camera.fill.badge.ellipsis")
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundStyle(.white)

                VStack(spacing: 4) {
                    Text(camera.authorizationStatus == .authorized ? "相机准备中" : "需要相机权限")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.white)
                    Text(camera.statusText)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white.opacity(0.72))
                        .multilineTextAlignment(.center)
                }

                if camera.authorizationStatus != .authorized {
                    Button {
                        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                        UIApplication.shared.open(url)
                    } label: {
                        Text("打开系统设置")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 9)
                            .background(.white, in: Capsule())
                    }
                    .buttonStyle(PressableButtonStyle())
                }
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 20)
            .background(.black.opacity(0.54), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(.white.opacity(0.12), lineWidth: 1)
            }
            .padding(.horizontal, 32)
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

    private var controls: some View {
        HStack(spacing: 34) {
            Button {
                if hasHermesResult {
                    clearHermesSession()
                } else {
                    triggerManualHermes()
                }
            } label: {
                Image(systemName: hasHermesResult ? "xmark.circle.fill" : "sparkles")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 62, height: 62)
                    .background(.black.opacity(0.44), in: Circle())
                    .overlay {
                        Circle()
                            .stroke(.white.opacity(0.18), lineWidth: 1)
                    }
            }
            .opacity(settings.hermesMode.allowsManual ? 1 : 0.45)
            .buttonStyle(PressableButtonStyle())
            .accessibilityLabel(hasHermesResult ? "退出识别" : "Hermes 识别")

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
                clearHermesSession(restoreCamera: false, showFeedback: false)
                camera.switchCamera()
                buttonFeedback(camera.cameraPosition == .back ? "切换前置相机" : "切换后置相机")
            } label: {
                Image(systemName: "arrow.triangle.2.circlepath.camera")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 62, height: 62)
                    .background(.black.opacity(0.44), in: Circle())
                    .overlay {
                        Circle()
                            .stroke(.white.opacity(0.18), lineWidth: 1)
                    }
            }
            .buttonStyle(PressableButtonStyle())
            .accessibilityLabel("切换前后相机")
        }
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
