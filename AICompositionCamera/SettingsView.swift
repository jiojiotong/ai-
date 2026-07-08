import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: SettingsStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Hermes 分析") {
                    Picker("模式", selection: $settings.hermesMode) {
                        ForEach(HermesMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }

                    Picker("自动间隔", selection: $settings.automaticHermesInterval) {
                        Text("5 秒").tag(TimeInterval(5))
                        Text("10 秒").tag(TimeInterval(10))
                        Text("15 秒").tag(TimeInterval(15))
                        Text("30 秒").tag(TimeInterval(30))
                    }

                    TextField("私有网关 API Key（可不填）", text: $settings.apiKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    TextField("中转站地址，例如 https://api.anyther.top/hermes-ai-camera/v1", text: $settings.apiBaseURL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    TextField("模型", text: $settings.model)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                Section("AI 大脑") {
                    Button {
                        settings.useHermesCameraBrain()
                    } label: {
                        Label(
                            settings.isUsingHermesCameraBrain ? "已使用 Hermes 相机大脑" : "使用 Hermes 相机大脑",
                            systemImage: settings.isUsingHermesCameraBrain ? "checkmark.seal.fill" : "brain.head.profile"
                        )
                    }

                    LabeledContent("地址", value: SettingsStore.hermesCameraBaseURL)
                    LabeledContent("模型", value: SettingsStore.hermesCameraModel)

                    Text("Hermes 相机大脑部署在你的服务器上，使用 ai-camera-agent 资料库生成取景动作、变焦建议和滤镜推荐。默认网关已在服务器侧鉴权，只有切到私有网关时才需要填写 API Key。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
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
                    Text("端侧实时构图、滤镜分类和轻美颜不会上传画面。开启 Hermes 后，应用会把当前取景帧压缩后发送到你的相机大脑，用于生成拍摄动作和滤镜推荐。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("说明") {
                    Text("Hermes 会像取景器教练一样返回可执行的移动方向、取景倍率、靠近/后退和滤镜建议。")
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
