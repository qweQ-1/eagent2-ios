import Foundation

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

    public nonisolated static var specs: [ToolSpec] { ToolCatalog.all }

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
