import SwiftUI

/// 安全门弹窗：逐条审批模型发起的工具调用。倒计时结束按原版行为默认执行，可随时改判。
struct SecuritySheet: View {
    let request: SecurityGate.PendingRequest
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var gate: SecurityGate
    @State private var seconds: Int
    @State private var timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    @Environment(\.dismiss) private var dismiss

    init(request: SecurityGate.PendingRequest) {
        self.request = request
        _seconds = State(initialValue: AppSettings().gateSeconds)
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("安全警告")
                        .font(.title2.bold())
                        .foregroundColor(.orange)
                    Spacer()
                    Text("\(max(seconds, 0))s")
                        .font(.title3.monospacedDigit())
                        .foregroundColor(seconds <= 3 ? .red : .primary)
                }
                Text("DeepSeek 请求执行以下操作：")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(toolLine).font(.headline.monospaced())
                        if let note = request.note, !note.isEmpty {
                            Text("意图：\(note)").font(.subheadline)
                        }
                        Text(request.argsText)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(4)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("倒计时：\(seconds) 秒").font(.caption).foregroundColor(.secondary)
                    Slider(value: Binding(get: { Double(seconds) }, set: { seconds = Int($0) }), in: 1...20, step: 1)
                    Text("倒计时结束将自动执行（原版默认行为）；你随时可以改判。").font(.caption2).foregroundColor(.secondary)
                }

                Spacer()

                HStack(spacing: 10) {
                    Button("中止任务") {
                        stopTimer()
                        gate.resolve(.abort)
                        dismiss()
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)

                    Button("跳过此项") {
                        stopTimer()
                        gate.resolve(.skip)
                        dismiss()
                    }
                    .buttonStyle(.bordered)

                    Button("立即执行") {
                        stopTimer()
                        gate.resolve(.run)
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(16)
            .onReceive(timer) { _ in
                if seconds > 0 { seconds -= 1 }
                if seconds <= 0 {
                    stopTimer()
                    gate.resolve(.run) // GatePolicy: 超时默认执行（原版行为）
                    dismiss()
                }
            }
        }
        .presentationDetents([.medium])
        .interactiveDismissDisabled()
    }

    private func stopTimer() { timer.upstream.connect().cancel() }

    private var toolLine: String {
        "[\(request.index)/\(request.total)] \(request.tool)"
    }
}
