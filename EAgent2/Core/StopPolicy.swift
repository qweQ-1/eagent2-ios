import Foundation

/// 任务终止的原因。
public enum StopReason: Equatable {
    /// 模型明确完成并给出了结论
    case completed
    /// 模型表示无法完成（缺权限、缺信息、做不到等）
    case impossible
    /// 模型没有实质产出（空回复、纯客套、复读）
    case idle
    /// 同一个工具连续失败多次
    case repeatedFailure(tool: String, count: Int)
    /// 达到最大轮数
    case maxRounds
    /// 等待回复超时
    case timeout
    /// 用户手动停止
    case userStopped
    /// 运行出错
    case error(String)

    public var title: String {
        switch self {
        case .completed:      return "任务完成"
        case .impossible:    return "无法完成"
        case .idle:          return "无实质进展"
        case .repeatedFailure: return "连续失败"
        case .maxRounds:     return "达到最大轮数"
        case .timeout:       return "等待超时"
        case .userStopped:   return "已手动停止"
        case .error:         return "出错"
        }
    }

    public var symbol: String {
        switch self {
        case .completed:      return "✅"
        case .impossible:    return "⛔️"
        case .idle:          return "💤"
        case .repeatedFailure: return "🔁"
        case .maxRounds:     return "🧱"
        case .timeout:       return "⏱"
        case .userStopped:   return "⏹"
        case .error:         return "❌"
        }
    }

    /// 属于「暂停」而不是「硬失败」：暂停后可以追加指令继续。
    public var isPause: Bool {
        switch self {
        case .completed, .impossible, .idle, .maxRounds, .timeout:
            return true
        case .repeatedFailure, .userStopped, .error:
            return false
        }
    }
}

/// 终止判定的纯逻辑（可单测，不依赖 WebView）。
public enum StopPolicy {

    // MARK: 信号词

    /// 表示「做不到 / 无法完成」的信号
    public static let impossibleMarkers: [String] = [
        "无法完成", "不能完成", "无法做到", "做不到", "无法实现",
        "我无法", "我不能", "我没法", "我做不到", "我无法办到",
        "无法访问", "无法连接", "无法获取", "无法读取", "无法写入",
        "没有权限", "权限不足", "未获得权限", "缺少权限",
        "未能完成", "未能找到", "未找到", "无法确定", "无法判断",
        "不支持", "不可用", "被拒绝", "拒绝了", "失败了", "失败：",
        "抱歉，我", "对不起，我", "请提供", "需要您提供", "需要你提供",
        "请确认是否", "请手动", "建议您手动", "建议你自己"
    ]

    /// 表示「没有实质产出」的信号
    public static let idleMarkers: [String] = [
        "你好", "您好", "在的", "有什么可以帮", "需要我做什么",
        "请告诉我", "你想让我", "有什么想让我", "ok", "好的"
    ]

    // MARK: 判定

    /// 回复是否表示「无法完成」。
    /// 注意：只在**没有后续工具调用**的前提下才据此暂停——
    /// 模型说「我无法直接读相册，但可以用 xxx 工具」是正常的下一步，不算失败。
    public static func looksImpossible(_ text: String) -> Bool {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if t.isEmpty { return false }
        for m in impossibleMarkers where t.contains(m) { return true }
        return false
    }

    /// 回复是否「没有实质产出」：太短、或只有寒暄。
    public static func looksIdle(_ text: String) -> Bool {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return true }
        // 去掉标点后太短
        let bare = t.replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: "。", with: "")
            .replacingOccurrences(of: "，", with: "")
            .replacingOccurrences(of: "！", with: "")
            .replacingOccurrences(of: "？", with: "")
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: "!", with: "")
            .replacingOccurrences(of: "?", with: "")
        if bare.count <= 4 { return true }
        // 纯寒暄
        let low = t.lowercased()
        for m in idleMarkers where low == m || low.hasPrefix(m) { return true }
        return false
    }

    /// 工具结果是否表示失败。
    public static func isFailedResult(_ result: String) -> Bool {
        guard let data = result.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return false
        }
        if let ok = obj["ok"] as? NSNumber { return !ok.boolValue }
        if let ok = obj["ok"] as? Bool { return !ok }
        return false
    }

    /// 连续失败计数是否达到阈值。
    public static func shouldPauseOnFailure(tool: String, streak: Int, threshold: Int) -> Bool {
        threshold > 0 && streak >= threshold
    }
}
