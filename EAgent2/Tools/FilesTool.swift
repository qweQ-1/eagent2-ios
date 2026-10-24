import Foundation

/// 工作区文件工具：只允许访问 root 目录内（对应 PC 版「选择工作目录」的沙盒化）。
public enum FilesTool {

    /// 把模型给的相对路径解析成 root 内的绝对 URL；越界返回 nil。
    public static func resolve(_ path: String, root: URL) -> URL? {
        var p = path.trimmingCharacters(in: .whitespacesAndNewlines)
        if p.isEmpty { return root }
        // 去掉前导 "/" 和常见的 "workspace/" 前缀
        while p.hasPrefix("/") { p.removeFirst() }
        if p.hasPrefix("workspace/") { p = String(p.dropFirst("workspace/".count)) }
        if p.isEmpty { return root }
        let composed = root.appendingPathComponent(p).standardizedFileURL
        // 必须仍在 root 内（root 本身也标准化）
        let rootStd = root.standardizedFileURL
        if composed == rootStd { return rootStd }
        guard composed.path.hasPrefix(rootStd.path + "/") else { return nil }
        return composed
    }

    public static func list(root: URL, path: String) -> String {
        guard let url = resolve(path, root: root) else { return err("路径越界或非法：" + path) }
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else {
            return err("目录不存在：" + display(url, root: root))
        }
        do {
            let items = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey])
            var out: [[String: String]] = []
            for item in items.prefix(200) {
                let vals = try? item.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
                out.append([
                    "name": item.lastPathComponent,
                    "type": (vals?.isDirectory ?? false) ? "dir" : "file",
                    "size": String(vals?.fileSize ?? 0)
                ])
            }
            return ok(["path": display(url, root: root), "count": String(out.count), "items": jsonString(out)])
        } catch {
            return err("读取目录失败：" + error.localizedDescription)
        }
    }

    public static func read(root: URL, path: String, maxChars: Int = 8000) -> String {
        guard let url = resolve(path, root: root) else { return err("路径越界或非法：" + path) }
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), !isDir.boolValue else {
            return err("文件不存在：" + display(url, root: root))
        }
        do {
            let data = try Data(contentsOf: url)
            var text = String(decoding: data, as: UTF8.self)
            var truncated = false
            if text.count > maxChars {
                text = String(text.prefix(maxChars))
                truncated = true
            }
            return ok(["path": display(url, root: root), "bytes": String(data.count),
                       "truncated": truncated ? "true" : "false", "content": text])
        } catch {
            return err("读取失败：" + error.localizedDescription)
        }
    }

    public static func write(root: URL, path: String, content: String) -> String {
        guard let url = resolve(path, root: root) else { return err("路径越界或非法：" + path) }
        let dir = url.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try Data(content.utf8).write(to: url, options: .atomic)
            return ok(["path": display(url, root: root), "bytes": String(Data(content.utf8).count)])
        } catch {
            return err("写入失败：" + error.localizedDescription)
        }
    }

    /// 显示给模型的相对路径（相对工作区根）
    public static func display(_ url: URL, root: URL) -> String {
        let rootStd = root.standardizedFileURL
        let p = url.standardizedFileURL.path
        if p == rootStd.path { return "/" }
        if p.hasPrefix(rootStd.path + "/") {
            return "/" + String(p.dropFirst(rootStd.path.count + 1))
        }
        return p
    }

    public static func ok(_ dict: [String: String]) -> String {
        var d = dict
        d["ok"] = "true"
        return jsonString(d)
    }

    public static func err(_ msg: String) -> String {
        return jsonString(["ok": "false", "error": msg])
    }

    public static func jsonString(_ obj: Any) -> String {
        if let data = try? JSONSerialization.data(withJSONObject: obj), let s = String(data: data, encoding: .utf8) {
            return s
        }
        return "{\"ok\":false,\"error\":\"结果序列化失败\"}"
    }
}
