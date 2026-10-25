import Foundation
import WebKit

/// DeepSeek 网页版注入桥：输入/发送/停止生成/读取回复/抓登录态。
/// 选择器全部多级兜底（官方改类名也能活）：类名 → aria-label → 文本启发式。
@MainActor
public final class WebBridge: ObservableObject {

    public static let chatURL = URL(string: "https://chat.deepseek.com/")!

    @Published public var loginDetected = false
    @Published public var tokenCaptured = false
    @Published public var inputReady = false
    @Published public var generating = false
    @Published public var lastError: String?

    /// 必须弱引用：WKWebView → configuration → userContentController → coordinator → bridge → webView
    /// 若强引用会形成循环引用，聊天页每次进入都永久泄漏一个 WKWebView（数十 MB），
    /// 在低内存设备上导致 WebContent 进程被系统回收 → 表现为「一进聊天框就闪退」。
    public private(set) weak var webView: WKWebView?
    private var observedURL: URL?

    public init() {}

    /// 挂载 WebView。必须在主线程同步调用，否则 attach 完成前 ensureChatPage 会误判「还没有 WebView」。
    public func attach(_ wv: WKWebView) {
        webView = wv
    }

    /// WebView 被 SwiftUI 拆除时调用，及时断开引用。
    public func detach() {
        webView = nil
    }

    // MARK: - 导航

    public func ensureChatPage() {
        guard let wv = webView else { return }
        if let url = wv.url, url.host?.contains("deepseek.com") == true { return }
        if wv.url == nil {
            wv.load(URLRequest(url: Self.chatURL))
        }
    }

    public func openChatPage() {
        guard let wv = webView else { return }
        wv.load(URLRequest(url: Self.chatURL))
    }

    public func reload() {
        webView?.reload()
    }

    // MARK: - JS 执行

    private func evalJS(_ js: String) async -> Any? {
        guard let wv = webView else { return nil }
        do {
            return try await wv.evaluateJavaScript(js)
        } catch {
            lastError = "JS 执行失败：\(error.localizedDescription)"
            return nil
        }
    }

    /// 调用注入的桥函数。
    ///
    /// 传参方式：把 payload 作为 JSON 字面量嵌入调用表达式。
    ///
    /// 为什么不直接用 callAsyncJavaScript 的 arguments：
    /// WebKit 的 `arguments` 在 JS 侧的实际形态随版本变化（可能是数组、字典或嵌套结构），
    /// 很容易取到 undefined，进而把字符串 "undefined" 填进 DeepSeek 输入框。
    /// 这里用 JSONSerialization 严格转义后再嵌入，是确定性的做法。
    private func callBridge(_ fn: String, _ arg: String? = nil) async -> Any? {
        guard let wv = webView else { return nil }
        let call: String
        if let arg {
            guard let literal = jsonLiteral(arg) else {
                lastError = "参数编码失败"
                return nil
            }
            call = "EAgentBridge.\(fn)(\(literal))"
        } else {
            call = "EAgentBridge.\(fn)()"
        }
        do {
            return try await wv.evaluateJavaScript(call)
        } catch {
            lastError = "JS 执行失败：\(error.localizedDescription)"
            return nil
        }
    }

    /// 把任意字符串编码成安全的 JSON 字面量（含引号/换行/反斜杠/控制字符都能正确转义）。
    private func jsonLiteral(_ s: String) -> String? {
        guard let data = try? JSONSerialization.data(withJSONObject: [s]),
              let arr = String(data: data, encoding: .utf8),
              arr.hasPrefix("["), arr.hasSuffix("]") else { return nil }
        // data 形如 ["..."]，去掉外层方括号得到字面量
        return String(arr.dropFirst().dropLast())
    }

    // MARK: - 状态

    public struct State: Equatable {
        public var login: Bool
        public var hasInput: Bool
        public var generating: Bool
        public var replyLen: Int
    }

    /// 调用桥函数并把返回的 JSON 字符串解析成字典。
    private func callBridgeJSON(_ fn: String, _ arg: String? = nil) async -> [String: Any]? {
        guard let out = await callBridge(fn, arg) else { return nil }
        if let dict = out as? [String: Any] { return dict }
        if let s = out as? String, let d = s.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any] {
            return obj
        }
        return nil
    }

    public func state() async -> State? {
        guard let d = await callBridgeJSON("state") else { return nil }
        return State(
            login: (d["login"] as? NSNumber)?.boolValue ?? false,
            hasInput: (d["hasInput"] as? NSNumber)?.boolValue ?? false,
            generating: (d["generating"] as? NSNumber)?.boolValue ?? false,
            replyLen: (d["replyLen"] as? NSNumber)?.intValue ?? 0
        )
    }

    // MARK: - 发送

    public struct SendResult: Equatable {
        public var ok: Bool
        public var clicked: Bool
        public var leftChars: Int
        /// 实际写入输入框的字符数（用于校验是否真的把文本送进去了）
        public var sentChars: Int
        public var why: String?
    }

    public func send(text: String) async -> SendResult? {
        guard let d = await callBridgeJSON("send", text) else { return nil }
        return SendResult(
            ok: (d["ok"] as? NSNumber)?.boolValue ?? false,
            clicked: (d["clicked"] as? NSNumber)?.boolValue ?? false,
            leftChars: (d["leftChars"] as? NSNumber)?.intValue ?? 0,
            sentChars: (d["sent"] as? NSNumber)?.intValue ?? 0,
            why: d["why"] as? String
        )
    }

    public func pressEnterFallback() async -> Bool {
        guard let d = await callBridgeJSON("pressEnter") else { return false }
        return (d["ok"] as? NSNumber)?.boolValue ?? false
    }

    // MARK: - 读取回复

    public struct Collect: Equatable {
        public var len: Int
        public var text: String
        public var generating: Bool
        public var login: Bool
    }

    public func collect() async -> Collect? {
        guard let d = await callBridgeJSON("collect") else { return nil }
        loginDetected = (d["login"] as? NSNumber)?.boolValue ?? loginDetected
        generating = (d["generating"] as? NSNumber)?.boolValue ?? false
        return Collect(
            len: (d["len"] as? NSNumber)?.intValue ?? 0,
            text: d["text"] as? String ?? "",
            generating: (d["generating"] as? NSNumber)?.boolValue ?? false,
            login: (d["login"] as? NSNumber)?.boolValue ?? false
        )
    }

    // MARK: - 停止

    public func stopGeneration() async {
        _ = await callBridgeJSON("stop")
        generating = false
    }

    public func refreshFromState() {
        Task { @MainActor in
            if let s = await state() {
                loginDetected = s.login
                inputReady = s.hasInput
                generating = s.generating
            }
        }
    }

    public func noteTokenCaptured() {
        tokenCaptured = true
        loginDetected = true
    }

    public func noteWebError(_ message: String) {
        lastError = "网页加载失败：\(message)"
    }

    // MARK: - 内存压力

    /// 收到内存告警时的降载动作：停止加载 + 回收图片缓存。
    /// 目的是尽量避免 WebContent 进程被系统 jetsam 杀掉（表现为闪退）。
    public func handleMemoryWarning() {
        guard let wv = webView else { return }
        wv.stopLoading()
        WKWebsiteDataStore.default().removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
                                                modifiedSince: Date().addingTimeInterval(-60),
                                                completionHandler: {})
    }
}
