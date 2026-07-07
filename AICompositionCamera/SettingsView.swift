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

                    TextField("中转站地址，例如 https://api.openai.com/v1", text: $settings.apiBaseURL)
                        .keyboardType(.URL)
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

                    Picker("取景比例", selection: $settings.selectedAspectRatio) {
                        ForEach(ShootingAspectRatio.allCases) { ratio in
                            Text(ratio.title).tag(ratio)
                        }
                    }
                }

                Section("拍摄功能") {
                    Picker("当前模式", selection: $settings.selectedCameraMode) {
                        ForEach(CameraFeatureMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }

                    Picker("当前滤镜分类", selection: $settings.selectedFilterCategory) {
                        ForEach(FilterCategory.displayOrder, id: \.rawValue) { category in
                            Text(category.title).tag(category)
                        }
                    }

                    Picker("当前轻美颜", selection: $settings.selectedPortraitEnhancementID) {
                        ForEach(PortraitEnhancement.all) { enhancement in
                            Text(enhancement.title).tag(enhancement.id)
                        }
                    }
                }

                Section("滤镜") {
                    Picker("当前滤镜", selection: $settings.selectedFilterID) {
                        ForEach(PhotoFilter.all) { filter in
                            Text(filter.title).tag(filter.id)
                        }
                    }
                }

                Section("隐私") {
                    Text("端侧实时构图、滤镜分类和轻美颜不会上传画面。开启 GPT 分析后，应用会把当前取景帧压缩后发送到你配置的 GPT 接口或中转站，用于生成构图建议和滤镜推荐。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("说明") {
                    Text("AI 构图模式会把当前取景帧发送给你配置的 GPT 接口，让 GPT 像取景器教练一样返回可执行的移动、靠近、留白和角度建议。")
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
