import UIKit
import UserNotifications
import Foundation

/// 通知 / 剪贴板 / 设备信息 / 快捷指令。
public enum MiscTools {

    // MARK: 本地通知

    @MainActor
    public static func notify(title: String, body: String) async -> String {
        let center = UNUserNotificationCenter.current()
        let ok = await withCheckedContinuation { (c: CheckedContinuation<Bool, Never>) in
            center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in c.resume(returning: granted) }
        }
        guard ok else { return FilesTool.err("未获得通知权限，请在 设置 → EAgent 中允许通知") }
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return FilesTool.err("通知标题不能为空") }
        let content = UNMutableNotificationContent()
        content.title = t
        content.body = body
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let id = UUID().uuidString
        do {
            try await center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
            return FilesTool.ok(["notified": t])
        } catch {
            return FilesTool.err("发送通知失败：" + error.localizedDescription)
        }
    }

    // MARK: 剪贴板

    @MainActor
    public static func clipboard(action: String, text: String) -> String {
        switch action.trimmingCharacters(in: .whitespaces).lowercased() {
        case "set", "write", "copy":
            let t = text
            if t.isEmpty { return FilesTool.err("要写入剪贴板的内容为空") }
            UIPasteboard.general.string = t
            return FilesTool.ok(["copied": String(t.prefix(200)), "chars": String(t.count)])
        case "get", "read":
            let s = UIPasteboard.general.string ?? ""
            return FilesTool.ok(["clipboard": String(s.prefix(4000)), "chars": String(s.count)])
        default:
            return FilesTool.err("未知剪贴板动作（用 get 或 set）")
        }
    }

    // MARK: 设备信息

    @MainActor
    public static func deviceInfo() -> String {
        let device = UIDevice.current
        device.isBatteryMonitoringEnabled = true
        let battery = device.batteryLevel >= 0 ? String(format: "%.0f%%", device.batteryLevel * 100) : "unknown"
        device.isBatteryMonitoringEnabled = false

        var free = "unknown"
        if let attrs = try? FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory()),
           let bytes = attrs[.systemFreeSize] as? NSNumber {
            free = String(format: "%.1f GB", bytes.doubleValue / 1_073_741_824)
        }
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return FilesTool.ok([
            "model": device.model,
            "system": device.systemName + " " + device.systemVersion,
            "name": device.name,
            "battery": battery,
            "free_storage": free,
            "locale": Locale.current.identifier,
            "timezone": TimeZone.current.identifier,
            "app": "EAgent " + version + " (" + build + ")"
        ])
    }

    // MARK: 快捷指令

    @MainActor
    public static func runShortcut(name: String, input: String) async -> String {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if n.isEmpty { return FilesTool.err("快捷指令名不能为空") }
        var comps = URLComponents(string: "shortcuts://run-shortcut")
        comps?.queryItems = [
            URLQueryItem(name: "name", value: n),
            URLQueryItem(name: "input", value: input)
        ]
        guard let url = comps?.url else { return FilesTool.err("构造 shortcuts URL 失败") }
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            UIApplication.shared.open(url, options: [:]) { _ in c.resume() }
        }
        return FilesTool.ok(["shortcut": n, "note": "已唤起「快捷指令」App 执行，执行结果不会自动返回 EAgent"])
    }
}
