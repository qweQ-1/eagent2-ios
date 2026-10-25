import Foundation
import UIKit

// MARK: - 文件级工具（供 C 风格回调使用，不依赖 actor 隔离）

/// App 沙盒 Documents 目录。
private func eagentDocsURL() -> URL {
    FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        ?? URL(fileURLWithPath: NSTemporaryDirectory())
}

/// 写文本到 Documents。
private func eagentWrite(_ name: String, _ text: String) {
    let url = eagentDocsURL().appendingPathComponent(name)
    try? text.write(to: url, atomically: true, encoding: .utf8)
}

/// 崩溃时的全局落盘位置（供 C 风格的异常处理器访问，不能用捕获闭包）。
nonisolated(unsafe) private var crashSink: ((String) -> Void)?

/// 顶层 C 风格异常处理器：NSSetUncaughtExceptionHandler 不接受带捕获的闭包。
private func eagentExceptionHandler(_ exception: NSException) {
    let text = """
    时间：\(ISO8601DateFormatter().string(from: Date()))
    异常：\(exception.name.rawValue)
    原因：\(exception.reason ?? "unknown")
    调用栈：
    \(exception.callStackSymbols.joined(separator: "\n"))
    """
    crashSink?(text)
}

/// 崩溃防护与现场取证。
///
/// 1) 捕获 ObjC 侧未处理异常（Swift trap 抓不到，但 UIKit/ObjC 层的 NSException 可以）；
/// 2) 监听内存告警并广播（WKWebView 内容进程在低内存设备上容易被系统回收 → 表现为「闪退」）；
/// 3) 写「上次会话未正常结束」标记，下次启动可提示用户。
public enum CrashGuard {

    public static let crashFile = "eagent-last-crash.txt"
    public static let sessionFile = "eagent-session.marker"
    public static let memoryWarning = Notification.Name("eagent.memoryWarning")

    private static var installed = false

    // MARK: - 安装

    public static func install() {
        guard !installed else { return }
        installed = true

        crashSink = { text in eagentWrite(crashFile, text) }
        NSSetUncaughtExceptionHandler(eagentExceptionHandler)

        // 内存告警 → 广播给网页层，让它主动释放/重载
        NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil, queue: .main
        ) { _ in
            NotificationCenter.default.post(name: CrashGuard.memoryWarning, object: nil)
        }

        markRunning()
    }

    // MARK: - 会话标记

    private static func write(_ name: String, _ text: String) {
        eagentWrite(name, text)
    }

    private static func read(_ name: String) -> String? {
        let url = eagentDocsURL().appendingPathComponent(name)
        guard let s = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : s
    }

    /// 标记「本次运行中」。若下次启动时该标记仍在，说明上次是异常退出。
    private static func markRunning() {
        let stamp = ISO8601DateFormatter().string(from: Date())
        write(sessionFile, "running \(stamp) pid=\(ProcessInfo.processInfo.processIdentifier)")
    }

    /// App 正常进入后台/退出时清除标记。
    public static func markCleanExit() {
        try? FileManager.default.removeItem(at: eagentDocsURL().appendingPathComponent(sessionFile))
    }

    /// 上次是否异常退出（true = 上次没有走到正常收尾）。
    public static var previousRunCrashed: Bool {
        read(sessionFile) != nil
    }

    /// 上次崩溃的异常描述（若有）。
    public static var lastCrashText: String? {
        read(crashFile)
    }

    public static func clearLastCrash() {
        try? FileManager.default.removeItem(at: eagentDocsURL().appendingPathComponent(crashFile))
    }
}
