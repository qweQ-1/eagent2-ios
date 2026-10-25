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

    @MainActor
    public func request(tool: String, note: String?, args: [String: String], index: Int, total: Int) async -> GateDecision {
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

    public func resolve(_ decision: GateDecision) {
        pending = nil
        cont?.resume(returning: decision)
        cont = nil
    }

    static func prettyArgs(_ args: [String: String]) -> String {
        let body = args.sorted { $0.key < $1.key }.map { "\($0.key): \($0.value)" }.joined(separator: "\n")
        return body.isEmpty ? "（无参数）" : body
    }
}
