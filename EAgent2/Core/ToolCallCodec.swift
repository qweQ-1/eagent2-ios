import Foundation

/// 一次工具调用。对应模型回复里的 eagent 工具块。
public struct ToolCall: Equatable {
    public var tool: String
    public var args: [String: String]
    public var note: String?

    public init(tool: String, args: [String: String] = [:], note: String? = nil) {
        self.tool = tool
        self.args = args
        self.note = note
    }
}

public enum ToolCallParseResult: Equatable {
    case none            // 回复里没有工具调用 → 视为最终答复
    case found(ToolCall)
    case malformed(String)
}

/// eagent 工具块的编解码。
/// 约定：模型每轮至多输出一个
/// ```eagent
/// {"tool":"open_app","args":{"name":"微信"},"note":"打开微信"}
/// ```
/// 解析带多重兜底：围栏块优先 → 全文第一个含 "tool" 键的平衡 JSON 对象。
public enum ToolCallCodec {
    public static let fenceTag = "eagent"

    public static func encode(_ call: ToolCall) -> String {
        var obj: [String: Any] = ["tool": call.tool, "args": call.args]
        if let note = call.note { obj["note"] = note }
        if let data = try? JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys]),
           let s = String(data: data, encoding: .utf8) {
            return "```" + fenceTag + "\n" + s + "\n```"
        }
        return ""
    }

    public static func parse(from text: String) -> ToolCallParseResult {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return .none }

        // 1) 围栏块
        if let open = trimmed.range(of: "```" + fenceTag, options: [.caseInsensitive]) {
            let rest = trimmed[open.upperBound...]
            if let close = rest.range(of: "```") {
                let inner = String(rest[..<close.lowerBound])
                return decode(inner)
            }
        }

        // 2) 兜底：全文第一个平衡 JSON 对象且含 "tool"
        if let json = firstBalancedJSONObject(in: trimmed), json.contains("\"tool\"") {
            return decode(json)
        }
        return .none
    }

    /// 从字符串中取出第一个括号配平的 JSON 对象（忽略字符串内的括号与转义）
    static func firstBalancedJSONObject(in text: String) -> String? {
        let chars = Array(text)
        var depth = 0
        var start = -1
        var inString = false
        var escaped = false
        for i in 0..<chars.count {
            let c = chars[i]
            if inString {
                if escaped { escaped = false }
                else if c == "\\" { escaped = true }
                else if c == "\"" { inString = false }
                continue
            }
            if c == "\"" { inString = true; continue }
            if c == "{" {
                depth += 1
                if depth == 1 { start = i }
            } else if c == "}" {
                depth -= 1
                if depth == 0, start >= 0 {
                    return String(chars[start...i])
                }
                if depth < 0 { return nil }
            }
        }
        return nil
    }

    private static func decode(_ raw: String) -> ToolCallParseResult {
        let cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // 去掉可能残留的语言标记行
        let body = cleaned.hasPrefix(fenceTag) ? String(cleaned.dropFirst(fenceTag.count)) : cleaned

        guard let data = body.data(using: .utf8) else {
            return .malformed("无法读取工具块内容")
        }
        guard let obj = try? JSONSerialization.jsonObject(with: data) else {
            return .malformed("eagent 块不是合法 JSON")
        }
        guard let dict = obj as? [String: Any] else {
            return .malformed("eagent 块必须是 JSON 对象")
        }
        guard let tool = dict["tool"] as? String, !tool.isEmpty else {
            return .malformed("eagent 块缺少 tool 字段")
        }
        var args: [String: String] = [:]
        if let a = dict["args"] as? [String: Any] {
            for (k, v) in a { args[k] = stringify(v) }
        }
        let note = dict["note"] as? String
        return .found(ToolCall(tool: tool, args: args, note: note))
    }

    static func stringify(_ v: Any) -> String {
        if let s = v as? String { return s }
        if let n = v as? NSNumber {
            // JSON 的 true/false 是 CFBoolean，不能按数字输出 "1"/"0"
            if CFGetTypeID(n as CFTypeRef) == CFBooleanGetTypeID() {
                return n.boolValue ? "true" : "false"
            }
            return n.stringValue
        }
        if let d = try? JSONSerialization.data(withJSONObject: v), let s = String(data: d, encoding: .utf8) {
            return s
        }
        return String(describing: v)
    }
}
