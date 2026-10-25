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

        // 1) 围栏块：逐个尝试，优先取**工具名有效**的那个。
        //    原因：回复里可能同时出现「回显的系统提示词示例」和「真正的工具块」，
        //    取第一个会读到提示词里的 {"tool":"工具名"} → 工具名无效 → 工具用不了。
        if let block = lastValidFencedBlock(in: trimmed) {
            return decode(block)
        }
        if let block = lastFencedBlock(in: trimmed) {
            return decode(block)
        }

        // 2) 兜底：全文最后一个平衡 JSON 对象且含 "tool"
        //    用「最后一个」而不是「第一个」：正文里可能先出现系统提示词回显的示例，
        //    真正的工具块在末尾。
        if let json = lastBalancedJSONObject(in: trimmed), json.contains("\"tool\"") {
            return decode(json)
        }
        return .none
    }

    /// 从字符串中取出最后一个括号配平的 JSON 对象（忽略字符串内的括号与转义）
    static func lastBalancedJSONObject(in text: String) -> String? {
        let chars = Array(text)
        var depth = 0
        var start = -1
        var inString = false
        var escaped = false
        var last: String?
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
                    last = String(chars[start...i])
                }
                if depth < 0 { depth = 0; start = -1 }
            }
        }
        return last
    }

    /// 取出最后一个「工具名合法」的 ```eagent ... ``` 围栏块内容。
    /// 若没有任何合法块，返回 nil（交由调用方走其它解析路径）。
    static func lastValidFencedBlock(in text: String) -> String? {
        let tag = fenceTag
        var searchStart = text.startIndex
        var fallback: String?
        while let open = text.range(of: "```" + tag, options: [.caseInsensitive], range: searchStart..<text.endIndex) {
            let rest = text[open.upperBound...]
            guard let close = rest.range(of: "```") else { break }
            let inner = String(rest[..<close.lowerBound])
            fallback = inner
            if let tool = extractToolName(from: inner), ToolCatalog.names.contains(tool) {
                return inner
            }
            searchStart = close.upperBound
        }
        _ = fallback
        return nil
    }

    /// 从一段 JSON 文本里粗略取出 tool 字段的值。
    static func extractToolName(from json: String) -> String? {
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let t = obj["tool"] as? String, !t.isEmpty else { return nil }
        return t
    }

    /// 取出最后一个 ```eagent ... ``` 围栏块的内容。
    static func lastFencedBlock(in text: String) -> String? {
        let tag = fenceTag
        var searchStart = text.startIndex
        var result: String?
        while let open = text.range(of: "```" + tag, options: [.caseInsensitive], range: searchStart..<text.endIndex) {
            let rest = text[open.upperBound...]
            if let close = rest.range(of: "```") {
                result = String(rest[..<close.lowerBound])
                searchStart = close.upperBound
            } else {
                break
            }
        }
        return result
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
