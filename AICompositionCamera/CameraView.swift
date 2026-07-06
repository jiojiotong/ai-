import SwiftUI

struct CameraView: View {
    @StateObject private var settings = SettingsStore()
    @StateObject private var camera = CameraSessionController()
    @StateObject private var gptAdvisor = GPTCompositionAdvisor()
    @State private var showingSettings = false
    @State private var lastAutomaticAnalysis = Date.distantPast
    @State private var lastAutomaticSceneSignature = ""
    @State private var automaticRequestDates: [Date] = []

    var body: some View {
        ZStack {
            CameraPreviewView(session: camera.session)
                .ignoresSafeArea()

            OverlayView(result: camera.compositionResult, intensity: settings.overlayIntensity)
                .ignoresSafeArea()

            VStack {
                topBar
                Spacer()
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
                showingSettings = true
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(.black.opacity(0.35), in: Circle())
            }
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
                        settings.selectedFilterID = recommendedFilter.id
                    } label: {
                        Label("AI 推荐 \(recommendedFilter.title)\(filterReasonSuffix)", systemImage: "camera.filters")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
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
                    .buttonStyle(.plain)
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
            .disabled(!settings.gptMode.allowsManual || gptAdvisor.isAnalyzing)
            .opacity(settings.gptMode.allowsManual ? 1 : 0.45)

            Button {
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
        .padding(.top, 10)
    }

    private func triggerManualGPT() {
        Task {
            await gptAdvisor.analyze(
                image: camera.latestImage,
                localResult: camera.compositionResult,
                settings: settings
            )
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
}
