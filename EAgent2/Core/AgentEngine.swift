import Foundation

/// Agent 主循环：对应 PC 版的「分析本源码后总结」——代发消息、等回复、解析工具、执行、回灌，直到模型给出最终答复。
@MainActor
public final class AgentEngine: ObservableObject {

    public enum State: Equatable {
        case idle
        case sending
        case waitingReply
        case toolRunning(String)
        case finished(String)
        case failed(String)
        /// 主动暂停：模型说做完了/做不到/没进展，或连续失败。等待用户补充指令。
        case paused(StopReason, String)
    }

    @Published public private(set) var state: State = .idle
    @Published public private(set) var iteration: Int = 0
    @Published public private(set) var actionCount: Int = 0
    /// 暂停时的上下文，保存以便「继续」时无缝接着跑
    @Published public private(set) var pauseContext: PauseContext?

    /// 暂停上下文：保留最后一轮的提示词与历史，用于续跑
    public struct PauseContext {
        public var reason: StopReason
        public var summary: String
        public var lastPrompt: String
        public var lastReply: String
        public var round: Int
        public var failedStreak: Int
        public var failedTool: String
    }

    private let bridge: WebBridge
    private let gate: SecurityGate
    private let log: AgentLogStore
    private let settings: AppSettings
    private let router: ToolRouter

    private var task: Task<Void, Never>?
    private var stopRequested = false
    /// 运行代号：每次 start 自增。旧任务发现自己代号过期就立刻退出。
    /// 不这样做的话，stop() 把 stopRequested 置 true、随后的 start() 又置回 false，
    /// 被取消的旧任务会「复活」并与新任务并发，两边同时向 SecurityGate 请求审批 → 重复 resume → 崩溃。
    private var runID = 0
    /// 连续失败计数（同一工具）
    private var failedStreak = 0
    private var failedTool = ""

    public init(bridge: WebBridge, gate: SecurityGate, log: AgentLogStore, settings: AppSettings) {
        self.bridge = bridge
        self.gate = gate
        self.log = log
        self.settings = settings
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        self.router = ToolRouter(workspaceURL: docs.appendingPathComponent("workspace"))
    }

    public var workspacePath: String { router.workspaceURL.path }
    public var isRunning: Bool {
        switch state {
        case .sending, .waitingReply, .toolRunning: return true
        default: return false
        }
    }

    public func reset() {
        stop()
        state = .idle
        iteration = 0
        actionCount = 0
    }

    // MARK: - 启停

    public func start(userTask: String) {
        let t = userTask.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        stop()
        runID += 1
        let myID = runID
        stopRequested = false
        state = .sending
        log.user(t)
        task = Task { [weak self] in
            await self?.run(userTask: t, runID: myID)
        }
    }

    public func stop() {
        stopRequested = true
        runID += 1   // 作废当前运行代号，旧任务会在下一个检查点退出
        gate.resolve(.abort)
        Task { await bridge.stopGeneration() }
        task?.cancel()
        task = nil
    }

    /// 当前运行是否仍然有效（未被新任务顶替、未被停止）
    private func isCurrent(_ id: Int) -> Bool {
        id == runID && !stopRequested
    }

    // MARK: - 主循环

    private func run(userTask: String, runID myID: Int, firstRound: Int = 1) async {
        guard isCurrent(myID) else { return }
        let systemPrompt = PromptBuilder.systemPrompt(
            workspacePath: router.workspaceURL.path,
            tools: ToolRouter.specs,
            deviceLine: MiscTools.deviceInfo()
        )
        var prompt = PromptBuilder.taskMessage(userTask: userTask, systemPrompt: systemPrompt)
        var first = true
        var lastReplyText = ""

        for round in firstRound...max(settings.maxIterations, firstRound) {
            if !isCurrent(myID) { return }
            iteration = round
            state = .sending

            guard let sr = await bridge.send(text: prompt) else {
                finishFailed("网页没有响应：请确认已打开 DeepSeek 聊天页并登录")
                return
            }
            if !sr.ok {
                let reason: String
                switch sr.why {
                case "no-arg":      reason = "消息内容未能正确传给网页（参数编码异常）"
                case "no-textarea": reason = "找不到 DeepSeek 的输入框，页面可能没加载完或改版了"
                default:            reason = "无法在 DeepSeek 网页输入/发送：可能未登录或页面发生了变化"
                }
                finishFailed(reason)
                return
            }
            // 校验确实把文本写进去了：防止「填进去的是 undefined」这类静默失败
            if sr.sentChars == 0 && !prompt.isEmpty {
                finishFailed("消息没有真正写入 DeepSeek 输入框（可能是页面结构变化或参数传递失败）")
                return
            }
            // 防御：输入框仍有内容说明按钮点击没生效，补一记回车
            if sr.leftChars > 0 {
                try? await Task.sleep(nanoseconds: 700_000_000)
                _ = await bridge.pressEnterFallback()
            }
            log.system(first ? "✅ 已把任务发送给 DeepSeek（含系统提示词）" : "↩️ 已回灌工具结果，等待模型继续")
            first = false

            state = .waitingReply
            var lastText = ""
            var lastLen = -1
            var stable = 0
            let deadline = Date().addingTimeInterval(TimeInterval(settings.timeoutSeconds))
            var collected: String?

            while true {
                if !isCurrent(myID) || Task.isCancelled {
                    finishStopped("用户已停止")
                    return
                }
                try? await Task.sleep(nanoseconds: 500_000_000)
                guard let c = await bridge.collect() else {
                    if Date() > deadline {
                        finishFailed("等待回复超时（网页无响应）")
                        return
                    }
                    continue
                }
                if c.len == lastLen && c.len > 0 && !c.generating {
                    stable += 1
                } else {
                    stable = 0
                    lastLen = c.len
                    lastText = c.text
                }
                if stable >= 3 {
                    collected = lastText
                    break
                }
                if Date() > deadline {
                    finishFailed("等待 DeepSeek 回复超时（\(settings.timeoutSeconds)s），请重试或切换网络")
                    return
                }
            }

            let reply = (collected ?? lastText).trimmingCharacters(in: .whitespacesAndNewlines)
            if reply.isEmpty {
                finishFailed("没有读到 DeepSeek 的回复文本（页面结构可能变化）")
                return
            }
            lastReplyText = reply
            log.assistant(reply)

            switch ToolCallCodec.parse(from: reply) {
            case .none:
                // —— 自动截停判定 ——
                // 模型没有再请求工具，说明它认为这一轮就是最终答复。
                // 但若它明说「做不到 / 无法完成」，不该当作成功收工，
                // 应暂停下来告诉用户缺什么，等补充指令后再继续。
                if StopPolicy.looksImpossible(reply) {
                    pause(reason: .impossible, summary: reply, prompt: prompt, reply: reply, round: round, runID: myID)
                    return
                }
                if StopPolicy.looksIdle(reply) {
                    pause(reason: .idle,
                          summary: reply.isEmpty ? "模型没有给出任何有效内容" : reply,
                          prompt: prompt, reply: reply, round: round, runID: myID)
                    return
                }
                finishSuccess(reply)
                return

            case .malformed(let why):
                log.system("⚠️ 工具块解析失败：\(why)")
                prompt = PromptBuilder.malformedMessage(why, lastOutput: reply)

            case .found(let call):
                // 工具名不在目录里 → 多半是把系统提示词里的示例当成了工具块
                if !ToolCatalog.names.contains(call.tool) {
                    log.system("⚠️ 识别到的工具名「\(call.tool)」不存在，已忽略该轮工具块（可能是提示词回显被误读）")
                    finishFailed("识别到的工具「\(call.tool)」不是可用工具。可能是网页回读到的是本 App 发出的系统提示词，而不是 DeepSeek 的回复；请点「刷新」后重试。")
                    return
                }
                let args = SecurityGate.prettyArgs(call.args)
                let head = "🔧 [\(round)] \(call.tool)"
                log.system(head + "\n" + args + (call.note.map { "\n意图：\($0)" } ?? ""))

                if call.tool == "finish" {
                    let r = await router.call(call)
                    log.tool(name: call.tool, result: r)
                    finishSuccess(call.note ?? "任务完成")
                    return
                }

                let decision: GateDecision
                if settings.gateMode == .auto {
                    decision = .run
                } else {
                    // 审批前再次确认本次运行仍然有效：否则旧任务会和新任务同时向安全门请求，
                    // 造成 continuation 状态错乱。
                    guard isCurrent(myID) else { return }
                    decision = await gate.request(tool: call.tool, note: call.note, args: call.args, index: round, total: settings.maxIterations)
                    guard isCurrent(myID) else { return }
                }

                switch decision {
                case .abort:
                    finishStopped("用户在安全门中止了任务")
                    return
                case .skip:
                    prompt = PromptBuilder.feedMessage(tool: call.tool, result: "{\"ok\":false,\"error\":\"用户拒绝执行此工具，请改用其他方式或直接给出结论\"}")
                case .run:
                    state = .toolRunning(call.tool)
                    let result = await router.call(call)
                    actionCount += 1
                    log.tool(name: call.tool, result: result)

                    // —— 连续失败熔断 ——
                    // 同一个工具连续失败多次，说明模型在绕圈，停下来问用户。
                    if StopPolicy.isFailedResult(result) {
                        if call.tool == failedTool { failedStreak += 1 } else { failedTool = call.tool; failedStreak = 1 }
                        if StopPolicy.shouldPauseOnFailure(tool: call.tool, streak: failedStreak,
                                                          threshold: settings.failureStreakLimit) {
                            pause(reason: .repeatedFailure(tool: call.tool, count: failedStreak),
                                  summary: "工具「\(call.tool)」连续失败 \(failedStreak) 次，已暂停以免继续绕圈。",
                                  prompt: prompt, reply: reply, round: round, runID: myID)
                            return
                        }
                    } else {
                        failedStreak = 0
                        failedTool = ""
                    }

                    prompt = PromptBuilder.feedMessage(tool: call.tool, result: result)
                }
            }
        }
        pause(reason: .maxRounds,
              summary: "已达到最大轮数（\(settings.maxIterations)）仍未得出结论，已暂停。可在设置里调大轮数，或直接给出补充指令让它继续。",
              prompt: prompt, reply: lastReplyText, round: settings.maxIterations, runID: myID)
    }

    // MARK: - 暂停 / 继续

    /// 暂停任务：保存上下文，等用户补充指令后继续。
    private func pause(reason: StopReason, summary: String, prompt: String, reply: String, round: Int, runID myID: Int) {
        guard isCurrent(myID) else { return }
        state = .paused(reason, summary)
        pauseContext = PauseContext(
            reason: reason,
            summary: summary,
            lastPrompt: prompt,
            lastReply: reply,
            round: round,
            failedStreak: failedStreak,
            failedTool: failedTool
        )
        log.system("\(reason.symbol) 自动暂停：\(reason.title)\n\(summary)")
        task = nil
    }

    /// 用户补充指令后续跑：把补充内容喂给模型，从暂停处继续。
    public func resume(with instruction: String) {
        guard let ctx = pauseContext else { return }
        let extra = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !extra.isEmpty else { return }
        pauseContext = nil
        stop()
        runID += 1
        let myID = runID
        stopRequested = false
        failedStreak = 0
        failedTool = ""
        state = .sending
        log.system("▶️ 继续执行：\(extra)")

        // 续跑提示：保留上一轮结论 + 用户补充，要求模型接着做
        let followUp = PromptBuilder.resumeMessage(
            previousSummary: ctx.summary,
            userInstruction: extra,
            lastPrompt: ctx.lastPrompt
        )
        task = Task { [weak self] in
            await self?.run(userTask: followUp, runID: myID, firstRound: ctx.round + 1)
        }
    }

    /// 放弃当前任务，回到初始状态。
    public func abandon() {
        stop()
        pauseContext = nil
        state = .idle
        iteration = 0
        actionCount = 0
    }

    // MARK: - 收尾

    private func finishSuccess(_ summary: String) {
        state = .finished(summary)
        log.system("🏁 任务结束")
        task = nil
    }

    private func finishStopped(_ msg: String) {
        state = .failed(msg)
        log.system("⏹ " + msg)
        task = nil
    }

    private func finishFailed(_ msg: String) {
        state = .failed(msg)
        log.system("❌ " + msg)
        task = nil
    }
}
