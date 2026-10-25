import SwiftUI

/// 对话页：顶部状态 + DeepSeek 网页 + 任务输入条。
struct ChatTabView: View {
    @EnvironmentObject var bridge: WebBridge
    @EnvironmentObject var engine: AgentEngine
    @EnvironmentObject var settings: AppSettings
    @State private var taskText = ""
    /// 是否已加载网页。低内存设备上一进来就加载重网页极易被系统回收 → 闪退。
    /// 改为「点按进入」后才加载。
    @State private var webLoaded = false
    @State private var showLoadButton = true

    var body: some View {
        VStack(spacing: 0) {
            StatusBarView()
            ZStack {
                if webLoaded {
                    DeepSeekWebView(bridge: bridge)
                        .overlay(alignment: .top) {
                            if engine.isRunning {
                                RunBanner(engine: engine)
                                    .padding(.top, 6)
                            }
                        }
                } else {
                    PlaceholderView {
                        webLoaded = true
                    }
                }
            }
            if case .paused(let reason, let summary) = engine.state {
                PausePanel(reason: reason, summary: summary)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 6)
            }
            InputBar(text: $taskText, onSend: send)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
        }
        .background(Color(.systemGroupedBackground))
        .onAppear { }
    }

    private func send() {
        let t = taskText
        taskText = ""
        if !webLoaded {
            // 先确保网页已加载，再发送任务
            webLoaded = true
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 1_200_000_000)
                engine.start(userTask: t)
            }
        } else {
            engine.start(userTask: t)
        }
    }
}

/// 未加载网页时的占位视图：给出明确入口，避免一进页面就吃满内存。
private struct PlaceholderView: View {
    let onLoad: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "globe")
                .font(.system(size: 44))
                .foregroundColor(.secondary)
            Text("DeepSeek 聊天页尚未加载")
                .font(.headline)
            Text("在低内存设备上一进来就加载重网页极易被系统回收 → 闪退。\n需要对话时再点下面的按钮加载。")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 30)
            Button {
                onLoad()
            } label: {
                Label("加载 DeepSeek 页面", systemImage: "arrow.down.circle")
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
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
            if case .paused(let reason, _) = engine.state {
                Pill(label: "已暂停 · \(reason.title)", color: .orange)
            } else if bridge.generating || engine.isRunning {
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
        case .paused(let r, _): return "已暂停 · \(r.title)"
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


/// 暂停面板：Agent 主动停下来时，给出原因、结论，并允许用户补充指令后续跑。
private struct PausePanel: View {
    let reason: StopReason
    let summary: String
    @EnvironmentObject var engine: AgentEngine
    @State private var extra = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(reason.symbol)
                Text("已暂停 · \(reason.title)")
                    .font(.subheadline.bold())
                Spacer()
                Button("放弃任务") { engine.abandon() }
                    .font(.caption)
                    .foregroundColor(.red)
            }
            if !summary.isEmpty {
                Text(summary)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(4)
            }
            HStack(spacing: 8) {
                TextField("补充信息或新指令，让它继续", text: $extra, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...3)
                    .focused($focused)
                Button("继续") {
                    focused = false
                    let t = extra
                    extra = ""
                    engine.resume(with: t)
                }
                .buttonStyle(.borderedProminent)
                .disabled(extra.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(10)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
