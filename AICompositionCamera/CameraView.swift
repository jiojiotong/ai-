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
            CameraPreviewView(session: camera.session)
                .ignoresSafeArea()

            OverlayView(result: camera.compositionResult, intensity: settings.overlayIntensity)
                .ignoresSafeArea()

            VStack {
                topBar
                Spacer()
                feedbackToast
                advicePanel
                filterStrip
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

    private var advicePanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let suggestion = camera.compositionResult?.topSuggestion {
                Label(suggestion, systemImage: "viewfinder")
                    .font(.headline)
                    .foregroundStyle(.white)
            }

            if let photoStatus = camera.photoStatusText {
                Label(photoStatus, systemImage: "photo")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.95))
            }

            if gptAdvisor.isAnalyzing {
                Label("GPT 正在观察当前画面...", systemImage: "sparkles")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.9))
            } else if let advice = gptAdvisor.advice {
                Label(advice, systemImage: "sparkles")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.95))

                if let recommendedFilter = recommendedFilter {
                    Button {
                        buttonFeedback("已切换到 AI 推荐滤镜")
                        settings.selectedFilterID = recommendedFilter.id
                    } label: {
                        Label("AI 推荐 \(recommendedFilter.title)\(filterReasonSuffix)", systemImage: "camera.filters")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(PressableButtonStyle())
                }
            } else if let error = gptAdvisor.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.subheadline)
                    .foregroundStyle(.yellow)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.black.opacity(0.42), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var filterStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(PhotoFilter.all) { filter in
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
            }
            .padding(.horizontal, 2)
        }
        .padding(.top, 10)
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
                camera.capturePhoto()
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
        guard Date().timeIntervalSince(lastAutomaticAnalysis) >= settings.automaticGPTInterval else { return }
        guard hasAutomaticGPTBudget() else { return }

        let signature = camera.compositionResult?.sceneSignature ?? "no-result"
        guard signature != lastAutomaticSceneSignature else { return }

        lastAutomaticAnalysis = Date()
        lastAutomaticSceneSignature = signature
        automaticRequestDates.append(Date())
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

    private var filterReasonSuffix: String {
        guard let reason = gptAdvisor.filterReason, !reason.isEmpty else { return "" }
        return "：\(reason)"
    }

    private func filterBackground(_ filter: PhotoFilter) -> AnyShapeStyle {
        settings.selectedFilterID == filter.id ? AnyShapeStyle(.white.opacity(0.92)) : AnyShapeStyle(.black.opacity(0.35))
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
