import SwiftUI

struct SettingsTabView: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var engine: AgentEngine
    @State private var showTools = false

    var body: some View {
        NavigationStack {
            Form {
                Section("安全门（对应原版「安全警告」窗口）") {
                    Picker("审批模式", selection: $settings.gateMode) {
                        Text("逐条审批").tag(AppSettings.GateMode.ask)
                        Text("全自动（信任模型）").tag(AppSettings.GateMode.auto)
                    }
                    .pickerStyle(.segmented)
                    Stepper("倒计时 \(settings.gateSeconds) 秒", value: $settings.gateSeconds, in: 1...20)
                }

                Section("运行参数") {
                    Stepper("单轮等待上限 \(settings.timeoutSeconds) 秒", value: $settings.timeoutSeconds, in: 30...600, step: 30)
                    Stepper("最大轮数 \(settings.maxIterations)", value: $settings.maxIterations, in: 2...50)
                }

                Section("工作区") {
                    LabeledContent("路径", value: engine.workspacePath)
                    Text("文件工具只能读写此目录。可在 iOS「文件」App → 我的 iPhone → EAgent 中直接查看。")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Section("工具目录") {
                    Button(showTools ? "收起" : "查看全部 \(ToolRouter.specs.count) 个工具") { showTools.toggle() }
                    if showTools {
                        ForEach(ToolRouter.specs, id: \.name) { spec in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(spec.name).font(.subheadline.bold())
                                Text(spec.summary).font(.caption).foregroundColor(.secondary)
                            }
                        }
                    }
                }

                Section("关于") {
                    Text("EAgent iOS v1.0.0 —— 移植自 YaoGaoChaoLe/EAgent（GPL-3.0）")
                    Text("基于 DeepSeek 网页版自动化驱动，与反代一样违反 DeepSeek 用户协议；高频使用有风控风险，仅供学习交流。")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("设置")
        }
    }
}
