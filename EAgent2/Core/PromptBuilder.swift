import Foundation

/// 给 DeepSeek 网页版（无 system role，只能随首条用户消息下发）的系统提示词与任务消息拼装。
public struct PromptBuilder {

    /// 系统提示词：角色、环境、工具目录、输出协议、约束。
    public static func systemPrompt(workspacePath: String, tools: [ToolSpec], deviceLine: String) -> String {
        var lines: [String] = []
        lines.append("【EAgent · iPhone Agent 运行环境】")
        lines.append("你是一个运行在用户 iPhone 上的 AI Agent。你可以通过 EAgent 提供的原生工具真正操控这台手机，而不是只能聊天。")
        lines.append("")
        lines.append("环境信息：")
        lines.append("- " + deviceLine)
        lines.append("- 工作目录：\(workspacePath)（文件工具只能读写此目录内）")
        lines.append("- 时区：\(TimeZone.current.identifier)，当前时间：\(ISO8601Now())")
        lines.append("")
        lines.append("【原生工具目录】")
        for t in tools {
            lines.append("▸ \(t.name) — \(t.summary)")
            let args = t.argsDoc.split(separator: "\n").map { String($0) }
            for a in args where !a.trimmingCharacters(in: .whitespaces).isEmpty {
                lines.append("    \(a)")
            }
        }
        lines.append("")
        lines.append("【输出协议（必须严格遵守）】")
        lines.append("1. 需要操控手机时，你的整个回复中必须只包含一个代码块，语言标记固定为 eagent，内容是一个 JSON 对象：")
        lines.append("```eagent")
        lines.append("{\"tool\":\"工具名\",\"args\":{\"参数名\":\"参数值\"},\"note\":\"一句话说明你要做什么\"}")
        lines.append("```")
        lines.append("2. 每个回复最多输出一个 eagent 工具块。工具结果会由系统回灌给你，然后你再决定下一步。")
        lines.append("3. 不需要工具、任务已完成时，直接用自然语言给用户最终答复，不要再输出 eagent 块。")
        lines.append("4. 也可以主动调用 finish 工具结束任务并在 note 里给出结论。")
        lines.append("5. 参数值一律用字符串；日期时间优先用相对描述（如 \"明天上午9点\"、\"30分钟后\"），系统会解析。")
        lines.append("6. 除用户语言另有要求外，用简体中文与用户交流。")
        lines.append("")
        lines.append("【安全约束】")
        lines.append("- 文件操作仅限工作目录内；不得读写系统目录、不得尝试越狱类操作。")
        lines.append("- http_request 禁止访问内网/本机地址。")
        lines.append("- 敏感动作（发通知、开口播报、打开外部 App）前在 note 里说明影响，让用户知情。")
        lines.append("- 不确定当前设备能力时先调用 list_tools 或 device_info。")
        return lines.joined(separator: "\n")
    }

    /// 首条用户消息 = 系统提示词 + 用户任务（DeepSeek 网页版没有独立 system 通道）。
    public static func taskMessage(userTask: String, systemPrompt: String) -> String {
        var s = systemPrompt
        if !s.hasSuffix("\n") { s += "\n" }
        return s + "\n【用户任务】\n" + userTask
    }

    /// 把工具结果回灌给模型的用户消息。
    public static func feedMessage(tool: String, result: String) -> String {
        return """
        【工具结果 \(tool)】系统已执行完毕，结果如下（可能已截断）：
        \(result)

        请根据结果继续：若还需操控手机，只输出一个 eagent 工具块；任务已完成则直接给出最终总结，不要输出 eagent 块。
        """
    }

    public static func malformedMessage(_ reason: String, lastOutput: String) -> String {
        var s = "【系统提示】你上一轮的 eagent 工具块无法解析：\(reason)。请严格按协议重新只输出一个 eagent JSON 块；若不想执行工具，请直接文字答复。"
        if !lastOutput.isEmpty {
            s += "\n你上一轮输出的原文（供修正，截断至前 1500 字）：\n" + String(lastOutput.prefix(1500))
        }
        return s
    }

    static func ISO8601Now() -> String {
        let f = ISO8601DateFormatter()
        f.timeZone = TimeZone.current
        return f.string(from: Date())
    }
}
