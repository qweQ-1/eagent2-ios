import Foundation

/// 工具目录项（喂给 PromptBuilder 生成系统提示词）
public struct ToolSpec: Sendable {
    public var name: String
    public var summary: String
    public var argsDoc: String

    public init(name: String, summary: String, argsDoc: String) {
        self.name = name
        self.summary = summary
        self.argsDoc = argsDoc
    }
}

/// 工具目录（与 actor 无关，纯常量，任何上下文可读）
public enum ToolCatalog {
    public static let all: [ToolSpec] = [
        ToolSpec(name: "list_tools", summary: "查看可用工具与参数说明", argsDoc: "（无参数）"),
        ToolSpec(name: "open_app", summary: "按名称打开 iPhone 上的 App（微信/支付宝/设置/地图等）", argsDoc: "name: string 应用名或英文名"),
        ToolSpec(name: "open_url", summary: "打开网址或 URL Scheme（仅 http/https 与已知 scheme）", argsDoc: "url: string"),
        ToolSpec(name: "clipboard", summary: "读取/写入剪贴板", argsDoc: "action: get|set\ntext: string（set 时必填）"),
        ToolSpec(name: "read_file", summary: "读工作区内文本文件", argsDoc: "path: string 相对工作区的路径\nmax_chars: string 可选，默认 8000"),
        ToolSpec(name: "write_file", summary: "写文本文件到工作区（自动建目录）", argsDoc: "path: string\ncontent: string 完整内容"),
        ToolSpec(name: "list_files", summary: "列工作区内目录", argsDoc: "path: string 相对路径，\"\" 或 \"/\" 为根"),
        ToolSpec(name: "speak", summary: "用语音朗读文本（中文）", argsDoc: "text: string\nrate: string 可选 0.5~2.0"),
        ToolSpec(name: "notify", summary: "发一条本地通知", argsDoc: "title: string\nbody: string"),
        ToolSpec(name: "create_reminder", summary: "创建提醒事项", argsDoc: "title: string\ndue: string 如\"明天上午9点\"\nnotes: string 可选"),
        ToolSpec(name: "create_event", summary: "创建日历日程", argsDoc: "title: string\nstart: string\nduration_min: string 可选（默认60）\nnotes: string 可选"),
        ToolSpec(name: "get_weather", summary: "查询当前天气与今日概况（Open-Meteo）", argsDoc: "lat: string\nlon: string"),
        ToolSpec(name: "get_location", summary: "获取当前定位坐标", argsDoc: "（无参数）"),
        ToolSpec(name: "http_request", summary: "受限 https 请求（禁内网，响应截断）", argsDoc: "url: string\nmethod: string 可选 GET/POST\nbody: string 可选\nheaders: string 可选 JSON"),
        ToolSpec(name: "run_shortcut", summary: "唤起「快捷指令」App 执行指定指令", argsDoc: "name: string\ninput: string 可选"),
        ToolSpec(name: "device_info", summary: "查询设备型号/系统/电量/存储/时区", argsDoc: "（无参数）"),
        ToolSpec(name: "finish", summary: "显式结束任务", argsDoc: "note: string 结论摘要")
    ]

    public static var names: [String] { all.map { $0.name } }
}
