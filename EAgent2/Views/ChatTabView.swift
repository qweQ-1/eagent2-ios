import SwiftUI

/// 对话页：顶部状态 + DeepSeek 网页 + 任务输入条。
struct ChatTabView: View {
    @EnvironmentObject var bridge: WebBridge
    @EnvironmentObject var engine: AgentEngine
    @EnvironmentObject var settings: AppSettings
    @State private var taskText = ""

    var body: some View {
        VStack(spacing: 0) {
            StatusBarView()
            DeepSeekWebView(bridge: bridge)
                .overlay(alignment: .top) {
                    if engine.isRunning {
                        RunBanner(engine: engine)
                            .padding(.top, 6)
                    }
                }
            InputBar(text: $taskText, onSend: send)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
        }
        .background(Color(.systemGroupedBackground))
        .onAppear { bridge.ensureChatPage() }
    }

    private func send() {
        let t = taskText
        taskText = ""
        engine.start(userTask: t)
    }
}

private struct StatusBarView: View {
    @EnvironmentObject var bridge: WebBridge
    @EnvironmentObject var engine: AgentEngine

    var body: some View {
        HStack(spacing: 8) {
            Pill(label: bridge.loginDetected ? "已登录" : "未登录",
                 color: bridge.loginDetected ? .green : .red)
            Pill(label: bridge.inputReady ? "输入框就绪" : "输入框未就绪",
                 color: bridge.inputReady ? .blue : .gray)
            if bridge.generating || engine.isRunning {
                Pill(label: stateLabel, color: .orange)
            }
            Spacer()
            Button("刷新") { bridge.ensureChatPage(); bridge.reload() }
                .font(.caption)
            Button("打开聊天页") { bridge.openChatPage() }
                .font(.caption)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    private var stateLabel: String {
        switch engine.state {
        case .sending: return "发送中"
        case .waitingReply: return "等 DeepSeek 回复"
        case .toolRunning(let t): return "执行 \(t)"
        default: return bridge.generating ? "网页生成中" : "运行中"
        }
    }
}

struct Pill: View {
    var label: String
    var color: Color
    var body: some View {
        Text(label)
            .font(.caption2.bold())
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.15))
            .foregroundColor(color)
            .clipShape(Capsule())
    }
}

struct RunBanner: View {
    @ObservedObject var engine: AgentEngine
    var body: some View {
        HStack(spacing: 6) {
            ProgressView().scaleEffect(0.7)
            Text("第 \(engine.iteration) 轮 · 已执行 \(engine.actionCount) 个工具")
                .font(.caption)
            Spacer()
            Button("停止") { engine.stop() }
                .font(.caption.bold())
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
        .padding(.horizontal, 10)
    }
}

private struct InputBar: View {
    @Binding var text: String
    var onSend: () -> Void
    @EnvironmentObject var engine: AgentEngine
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 8) {
            TextField("给 DeepSeek 的任务，例如：建一个明天9点的提醒", text: $text, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...4)
                .focused($focused)
            if engine.isRunning {
                Button("停止") { engine.stop() }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
            } else {
                Button("发送任务") {
                    focused = false
                    onSend()
                }
                .buttonStyle(.borderedProminent)
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }
}
