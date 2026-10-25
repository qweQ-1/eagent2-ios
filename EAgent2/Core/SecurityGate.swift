import Foundation

/// 安全门（对应 PC 版「窗口_安全警告」）：3~20 秒倒计时，可整体切自动模式。
public enum GateDecision: Equatable {
    case run
    case skip
    case abort
}

/// 纯决策逻辑，可单测。
public enum GatePolicy {
    /// timeoutRuns：倒计时结束默认执行（原版默认行为）；否则默认跳过。
    public static func resolve(timeoutFired: Bool, user: GateDecision?, timeoutRuns: Bool) -> GateDecision {
        if let u = user { return u }
        if timeoutFired { return timeoutRuns ? .run : .skip }
        return .skip
    }
}

@MainActor
public final class SecurityGate: ObservableObject {
    public struct PendingRequest: Identifiable, Equatable {
        public let id = UUID()
        public var tool: String
        public var note: String?
        public var argsText: String
        var index: Int
        var total: Int

        public static func == (l: Self, r: Self) -> Bool { l.id == r.id }
    }

    @Published public private(set) var pending: PendingRequest?
    private var cont: CheckedContinuation<GateDecision, Never>?

    public init() {}

    /// 请求审批。注意：resume 同一个 continuation 两次会直接触发 Swift 运行时 fatalError，
    /// 因此必须保证「谁先到谁赢」，后来的请求只拿到 .abort。
    @MainActor
    public func request(tool: String, note: String?, args: [String: String], index: Int, total: Int) async -> GateDecision {
        // 已有未决请求：说明上一次没被正确收尾，直接中止本次，避免 continuation 泄漏与重复 resume
        if let existing = cont {
            cont = nil
            existing.resume(returning: .abort)
        }
        pending = PendingRequest(
            tool: tool,
            note: note,
            argsText: Self.prettyArgs(args),
            index: index,
            total: total
        )
        return await withCheckedContinuation { c in
            cont = c
        }
    }

    /// 幂等解析：只有第一次生效，重复调用（倒计时 + 按钮点击同时发生）不会重复 resume。
    public func resolve(_ decision: GateDecision) {
        pending = nil
        guard let c = cont else { return }
        cont = nil
        c.resume(returning: decision)
    }

    /// 纯函数，不依赖 actor 状态 → 必须标 nonisolated，否则非隔离上下文（测试）无法调用。
    nonisolated static func prettyArgs(_ args: [String: String]) -> String {
        let body = args.sorted { $0.key < $1.key }.map { "\($0.key): \($0.value)" }.joined(separator: "\n")
        return body.isEmpty ? "（无参数）" : body
    }
}
