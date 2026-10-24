import Foundation

/// 工具目录项（喂给 PromptBuilder 生成系统提示词）
public struct ToolSpec {
    public var name: String
    public var summary: String
    public var argsDoc: String

    public init(name: String, summary: String, argsDoc: String) {
        self.name = name
        self.summary = summary
        self.argsDoc = argsDoc
    }
}

/// 工具路由：从 ToolCall 分发到原生实现，统一返回 JSON 字符串。
@MainActor
public final class ToolRouter {

    public static let finishMarker = "eagent_finish"
    public let workspaceURL: URL
    private let locationProvider = LocationProvider()

    public init(workspaceURL: URL) {
        self.workspaceURL = workspaceURL
        ensureWorkspace()
    }

    public func ensureWorkspace() {
        var isDir: ObjCBool = false
        if !FileManager.default.fileExists(atPath: workspaceURL.path, isDirectory: &isDir) {
            try? FileManager.default.createDirectory(at: workspaceURL, withIntermediateDirectories: true)
        }
    }

    // MARK: - 目录

    public static var specs: [ToolSpec] {
        [
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
    }

    // MARK: - 分发

    public func call(_ call: ToolCall) async -> String {
        let a = call.args
        switch call.tool {

        case "list_tools":
            var items: [[String: String]] = []
            for s in Self.specs {
                items.append(["name": s.name, "summary": s.summary, "args": s.argsDoc])
            }
            return FilesTool.ok(["tools": FilesTool.jsonString(items)])

        case "open_app":
            guard let name = a["name"], !name.trimmingCharacters(in: .whitespaces).isEmpty else {
                return FilesTool.err("缺少参数 name")
            }
            if let scheme = OpenTool.schemeForApp(name), let url = OpenTool.safeURL(scheme) {
                return await OpenTool.open(url: url)
            }
            if let url = OpenTool.fallbackSearch(name) {
                return await OpenTool.open(url: url)
            }
            return FilesTool.err("无法识别的 App 名：" + name)

        case "open_url":
            guard let raw = a["url"], let url = OpenTool.safeURL(raw) else {
                return FilesTool.err("url 不合法或 scheme 不被允许（仅 http/https 与已知 scheme）")
            }
            return await OpenTool.open(url: url)

        case "clipboard":
            return MiscTools.clipboard(action: a["action"] ?? "get", text: a["text"] ?? "")

        case "read_file":
            guard let p = a["path"] else { return FilesTool.err("缺少参数 path") }
            let max = Int(a["max_chars"] ?? "") ?? 8000
            return FilesTool.read(root: workspaceURL, path: p, maxChars: max)

        case "write_file":
            guard let p = a["path"], let c = a["content"] else { return FilesTool.err("缺少参数 path/content") }
            return FilesTool.write(root: workspaceURL, path: p, content: c)

        case "list_files":
            return FilesTool.list(root: workspaceURL, path: a["path"] ?? "/")

        case "speak":
            guard let t = a["text"], !t.trimmingCharacters(in: .whitespaces).isEmpty else {
                return FilesTool.err("缺少参数 text")
            }
            return await SpeakTool.speak(t, rate: a["rate"] ?? "")

        case "notify":
            guard let t = a["title"], !t.trimmingCharacters(in: .whitespaces).isEmpty else {
                return FilesTool.err("缺少参数 title")
            }
            return await MiscTools.notify(title: t, body: a["body"] ?? "")

        case "create_reminder":
            guard let t = a["title"], !t.trimmingCharacters(in: .whitespaces).isEmpty else {
                return FilesTool.err("缺少参数 title")
            }
            return await EventKitTools.createReminder(title: t, notes: a["notes"] ?? "", due: a["due"] ?? "", timeZone: .current)

        case "create_event":
            guard let t = a["title"], !t.trimmingCharacters(in: .whitespaces).isEmpty else {
                return FilesTool.err("缺少参数 title")
            }
            let dur = Int(a["duration_min"] ?? "") ?? 60
            return await EventKitTools.createEvent(title: t, start: a["start"] ?? "", durationMin: dur, notes: a["notes"] ?? "", timeZone: .current)

        case "get_weather":
            guard let lat = Double((a["lat"] ?? "").trimmingCharacters(in: .whitespaces)),
                  let lon = Double((a["lon"] ?? "").trimmingCharacters(in: .whitespaces)) else {
                return FilesTool.err("缺少参数 lat/lon（可先调用 get_location）")
            }
            return await WeatherTool.run(lat: lat, lon: lon)

        case "get_location":
            return await locationProvider.current()

        case "http_request":
            guard let u = a["url"], !u.isEmpty else { return FilesTool.err("缺少参数 url") }
            let headers = parseHeaders(a["headers"])
            return await HTTPTool.run(url: u, method: a["method"] ?? "GET", body: a["body"], headers: headers)

        case "run_shortcut":
            guard let n = a["name"], !n.trimmingCharacters(in: .whitespaces).isEmpty else {
                return FilesTool.err("缺少参数 name")
            }
            return await MiscTools.runShortcut(name: n, input: a["input"] ?? "")

        case "device_info":
            return MiscTools.deviceInfo()

        case "finish":
            return FilesTool.ok(["summary": a["note"] ?? "任务完成", "finish": "true"])

        default:
            let names = Self.specs.map { $0.name }.joined(separator: ", ")
            return FilesTool.err("未知工具 \"\(call.tool)\"。可用工具：\(names)。请先读取上面的目录修正 tool 字段。")
        }
    }

    static func parseHeaders(_ s: String?) -> [String: String] {
        guard let s = s, !s.trimmingCharacters(in: .whitespaces).isEmpty,
              let data = s.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: String] else { return [:] }
        return obj
    }
}
