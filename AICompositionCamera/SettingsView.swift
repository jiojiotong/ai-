import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: SettingsStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("GPT 分析") {
                    Picker("模式", selection: $settings.gptMode) {
                        ForEach(GPTMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }

                    Picker("自动间隔", selection: $settings.automaticGPTInterval) {
                        Text("5 秒").tag(TimeInterval(5))
                        Text("10 秒").tag(TimeInterval(10))
                        Text("15 秒").tag(TimeInterval(15))
                        Text("30 秒").tag(TimeInterval(30))
                    }

                    TextField("OpenAI API Key", text: $settings.apiKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    TextField("模型", text: $settings.model)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                Section("构图辅助") {
                    Picker("叠加层", selection: $settings.overlayIntensity) {
                        ForEach(OverlayIntensity.allCases) { intensity in
                            Text(intensity.title).tag(intensity)
                        }
                    }
                }

                Section("隐私") {
                    Text("端侧实时构图不会上传画面。开启 GPT 分析后，应用会把当前取景帧压缩后发送到你配置的 GPT 接口，用于生成构图建议。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("设置")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}
