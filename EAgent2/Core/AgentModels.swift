import Foundation

// MARK: - Agent 消息记录

public enum AgentRole: String, Equatable {
    case user
    case assistant
    case tool
    case system
}

public struct AgentMessage: Identifiable, Equatable {
    public let id = UUID()
    public var role: AgentRole
    public var text: String
    public var time: Date
    /// 工具名（role == .tool 时使用）
    public var tool: String?

    public init(role: AgentRole, text: String, tool: String? = nil, time: Date = Date()) {
        self.role = role
        self.text = text
        self.tool = tool
        self.time = time
    }
}

@MainActor
public final class AgentLogStore: ObservableObject {
    @Published public private(set) var messages: [AgentMessage] = []

    public init() {}

    public func append(_ message: AgentMessage) {
        messages.append(message)
        if messages.count > 500 {
            messages.removeFirst(messages.count - 500)
        }
    }

    public func system(_ text: String) { append(.init(role: .system, text: text)) }
    public func user(_ text: String) { append(.init(role: .user, text: text)) }
    public func assistant(_ text: String) { append(.init(role: .assistant, text: text)) }
    public func tool(name: String, result: String) { append(.init(role: .tool, text: result, tool: name)) }
    public func clear() { messages.removeAll() }
}

// MARK: - 应用设置（持久化到 UserDefaults）

public final class AppSettings: ObservableObject {
    public enum GateMode: Int { case ask, auto }
    public enum Keys {
        public static let gateMode = "eagent.gateMode"
        public static let gateSeconds = "eagent.gateSeconds"
        public static let timeoutSeconds = "eagent.timeoutSeconds"
        public static let maxIterations = "eagent.maxIterations"
    }

    @Published public var gateMode: GateMode { didSet { store(gateMode.rawValue, Keys.gateMode) } }
    @Published public var gateSeconds: Int { didSet { store(gateSeconds, Keys.gateSeconds) } }
    @Published public var timeoutSeconds: Int { didSet { store(timeoutSeconds, Keys.timeoutSeconds) } }
    @Published public var maxIterations: Int { didSet { store(maxIterations, Keys.maxIterations) } }

    private let defaults = UserDefaults.standard

    public init() {
        let m = GateMode.ask.rawValue
        gateMode = GateMode(rawValue: defaults.object(forKey: Keys.gateMode) as? Int ?? m) ?? .ask
        gateSeconds = Self.clamp(defaults.integer(forKey: Keys.gateSeconds), min: 1, max: 60, fallback: 5)
        timeoutSeconds = Self.clamp(defaults.integer(forKey: Keys.timeoutSeconds), min: 30, max: 600, fallback: 240)
        maxIterations = Self.clamp(defaults.integer(forKey: Keys.maxIterations), min: 2, max: 50, fallback: 20)
    }

    private func store(_ v: Int, _ k: String) { defaults.set(v, forKey: k) }

    static func clamp(_ v: Int, min lo: Int, max hi: Int, fallback: Int) -> Int {
        if v < lo || v > hi { return fallback }
        return v
    }
}
