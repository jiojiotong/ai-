import SwiftUI

struct CameraView: View {
    @StateObject private var settings = SettingsStore()
    @StateObject private var camera = CameraSessionController()
    @StateObject private var gptAdvisor = GPTCompositionAdvisor()
    @State private var showingSettings = false
    @State private var lastAutomaticAnalysis = Date.distantPast

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
                controls
            }
            .padding()
        }
        .background(Color.black)
        .task {
            await camera.requestAccessAndStart()
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

            if gptAdvisor.isAnalyzing {
                Label("GPT 正在观察当前画面...", systemImage: "sparkles")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.9))
            } else if let advice = gptAdvisor.advice {
                Label(advice, systemImage: "sparkles")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.95))
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

        lastAutomaticAnalysis = Date()
        Task {
            await gptAdvisor.analyze(
                image: camera.latestImage,
                localResult: camera.compositionResult,
                settings: settings
            )
        }
    }
}
