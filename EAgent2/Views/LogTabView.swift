import SwiftUI

/// 记录页：Agent 全过程消息（任务/回复/工具调用/系统提示）。
struct LogTabView: View {
    @EnvironmentObject var log: AgentLogStore
    @EnvironmentObject var engine: AgentEngine

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("共 \(log.messages.count) 条")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                if case .paused(let reason, let s) = engine.state {
                    Text("已暂停(\(reason.title))：\(String(s.prefix(30)))")
                        .font(.caption)
                        .foregroundColor(.orange)
                } else if case .finished(let s) = engine.state {
                    Text("已完成：\(String(s.prefix(40)))")
                        .font(.caption)
                        .foregroundColor(.green)
                } else if case .failed(let s) = engine.state {
                    Text("失败：\(String(s.prefix(40)))")
                        .font(.caption)
                        .foregroundColor(.red)
                }
                Button("清空") { log.clear() }
                    .font(.caption)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(log.messages) { msg in
                            MessageRow(msg: msg)
                                .id(msg.id)
                        }
                    }
                    .padding(10)
                }
                .onChange(of: log.messages.count) { _ in
                    if let last = log.messages.last {
                        withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
            }
        }
    }
}

private struct MessageRow: View {
    let msg: AgentMessage

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(tag).font(.caption2.bold()).foregroundColor(color)
                Spacer()
                Text(msg.time, style: .time).font(.caption2).foregroundColor(.secondary)
            }
            Text(msg.text)
                .font(.callout)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(8)
        .background(color.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var tag: String {
        switch msg.role {
        case .user: return "任务"
        case .assistant: return "DeepSeek"
        case .tool: return "工具 \(msg.tool ?? "")"
        case .system: return "系统"
        }
    }

    private var color: Color {
        switch msg.role {
        case .user: return .blue
        case .assistant: return .purple
        case .tool: return .orange
        case .system: return .gray
        }
    }
}
