import SwiftUI

struct AISettingsView: View {
    @State private var isEnabled: Bool = UserDefaults.standard.bool(forKey: "deepseek_enabled")
    @State private var apiKey: String = ""
    @State private var modelName: String = UserDefaults.standard.string(forKey: "deepseek_model") ?? "deepseek-v4-pro"
    @State private var baseURL: String = UserDefaults.standard.string(forKey: "deepseek_base_url") ?? "https://api.deepseek.com"
    @State private var allowCloudSummary: Bool = UserDefaults.standard.bool(forKey: "allow_cloud_summary")
    @State private var isTestingConnection: Bool = false
    @State private var connectionStatus: String?
    @State private var connectionSuccess: Bool = false
    @State private var hasStoredKey: Bool = false

    var body: some View {
        Form {
            Section {
                Toggle("启用 DeepSeek AI", isOn: $isEnabled)
                    .onChange(of: isEnabled) { newValue in
                        UserDefaults.standard.set(newValue, forKey: "deepseek_enabled")
                    }

                Text("启用后将使用 DeepSeek V4 进行 AI 健康分析。关闭时使用本地规则引擎。")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section("API Key") {
                HStack {
                    SecureField("输入 API Key...", text: $apiKey)
                        .textFieldStyle(.roundedBorder)

                    Button(hasStoredKey ? "更新" : "保存到 Keychain") {
                        saveAPIKey()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(apiKey.trimmingCharacters(in: .whitespaces).isEmpty)
                }

                if hasStoredKey {
                    HStack {
                        Text("Keychain 中已有 API Key")
                            .font(.caption)
                            .foregroundColor(.green)

                        Button("删除") {
                            deleteAPIKey()
                        }
                        .buttonStyle(.borderless)
                        .font(.caption)
                        .foregroundColor(.red)
                    }
                }

                Button(action: testConnection) {
                    HStack {
                        if isTestingConnection {
                            ProgressView()
                                .scaleEffect(0.7)
                                .frame(width: 16, height: 16)
                        }
                        Text(isTestingConnection ? "测试中..." : "测试连接")
                    }
                }
                .buttonStyle(.bordered)
                .disabled(isTestingConnection || apiKey.trimmingCharacters(in: .whitespaces).isEmpty && !hasStoredKey)

                if let status = connectionStatus {
                    HStack {
                        Circle()
                            .fill(connectionSuccess ? Color.green : Color.red)
                            .frame(width: 8, height: 8)
                        Text(status)
                            .font(.caption)
                            .foregroundColor(connectionSuccess ? .green : .red)
                    }
                }

                Text("API Key 存储在 macOS Keychain 中，不会写入日志或源码。也可以在终端中设置环境变量 DEEPSEEK_API_KEY。")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section("模型配置") {
                TextField("模型名称", text: $modelName)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: modelName) { newValue in
                        UserDefaults.standard.set(newValue, forKey: "deepseek_model")
                    }

                TextField("Base URL", text: $baseURL)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: baseURL) { newValue in
                        UserDefaults.standard.set(newValue, forKey: "deepseek_base_url")
                    }

                Toggle("允许发送健康摘要到云端", isOn: $allowCloudSummary)
                    .onChange(of: allowCloudSummary) { newValue in
                        UserDefaults.standard.set(newValue, forKey: "allow_cloud_summary")
                    }

                Text("开启后 AI 请求会附带最近7-30天的健康摘要。原始数据不会上传。")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section("生成参数") {
                let genSettings = AIModelGenerationSettings.load()
                Stepper("Max Tokens: \(genSettings.maxTokens)", value: Binding(
                    get: { genSettings.maxTokens },
                    set: { var s = AIModelGenerationSettings.load(); s.maxTokens = $0; s.save() }
                ), in: 512...16384, step: 512)
                Stepper("Temperature: \(String(format: "%.1f", genSettings.temperature))", value: Binding(
                    get: { genSettings.temperature },
                    set: { var s = AIModelGenerationSettings.load(); s.temperature = $0; s.save() }
                ), in: 0.0...1.5, step: 0.1)
                Toggle("回答被截断时自动继续生成", isOn: Binding(
                    get: { genSettings.autoContinueWhenTruncated },
                    set: { var s = AIModelGenerationSettings.load(); s.autoContinueWhenTruncated = $0; s.save() }
                ))
                Text("当 DeepSeek 回答因长度限制被截断时，自动发送 continuation 请求继续生成。最多 3 次。")
                    .font(.caption).foregroundColor(.secondary)
            }

            Section("当前 AI 模式") {
                HStack {
                    Text("模式")
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(currentAIMode)
                        .fontWeight(.medium)
                }

                if !isEnabled {
                    Text("本地规则引擎正在运行。")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else if !hasStoredKey && apiKey.isEmpty {
                    Text("API Key 未配置，将使用本地规则引擎。")
                        .font(.caption)
                        .foregroundColor(.orange)
                } else {
                    Text("DeepSeek V4 就绪。")
                        .font(.caption)
                        .foregroundColor(.green)
                }
            }
        }
        .formStyle(.grouped)
        .task {
            await checkExistingKey()
        }
    }

    private var currentAIMode: String {
        if !isEnabled { return "Local Rules" }
        if hasStoredKey || !apiKey.isEmpty { return "DeepSeek V4" }
        return "Local Rules"
    }

    private func checkExistingKey() async {
        if let key = try? KeychainService.shared.getAPIKey() {
            hasStoredKey = true
            apiKey = key
        }
    }

    private func saveAPIKey() {
        let key = apiKey.trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty else { return }
        Task {
            try? await KeychainService.shared.saveAPIKey(key)
            hasStoredKey = true
            connectionStatus = "已保存到 Keychain"
            connectionSuccess = true
        }
    }

    private func deleteAPIKey() {
        Task {
            try? await KeychainService.shared.deleteAPIKey()
            hasStoredKey = false
            apiKey = ""
            connectionStatus = nil
        }
    }

    private func testConnection() {
        isTestingConnection = true
        connectionStatus = nil

        Task {
            // Save key first if entered but not saved
            if !apiKey.trimmingCharacters(in: .whitespaces).isEmpty && !hasStoredKey {
                try? await KeychainService.shared.saveAPIKey(apiKey.trimmingCharacters(in: .whitespaces))
            }

            do {
                let success = try await DeepSeekClient.shared.testConnection()
                connectionSuccess = success
                connectionStatus = success ? "连接成功" : "连接失败"
            } catch {
                connectionSuccess = false
                connectionStatus = error.localizedDescription
            }
            isTestingConnection = false
        }
    }
}
