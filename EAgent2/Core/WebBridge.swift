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

    public private(set) var webView: WKWebView?
    private var observedURL: URL?

    public init() {}

    public func attach(_ wv: WKWebView) {
        webView = wv
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

    private func jsString(_ s: String) -> String {
        if let data = try? JSONSerialization.data(withJSONObject: s), let str = String(data: data, encoding: .utf8) {
            return str
        }
        return "\"\""
    }

    private func callBridge(_ fn: String, _ arg: String? = nil) async -> [String: Any]? {
        let call = arg.map { "EAgentBridge.\(fn)(\(jsString($0)))" } ?? "EAgentBridge.\(fn)()"
        let out = await evalJS(call)
        if let s = out as? String, let d = s.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any] {
            return obj
        }
        return nil
    }

    // MARK: - 状态

    public struct State: Equatable {
        public var login: Bool
        public var hasInput: Bool
        public var generating: Bool
        public var replyLen: Int
    }

    public func state() async -> State? {
        guard let d = await callBridge("state") else { return nil }
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
    }

    public func send(text: String) async -> SendResult? {
        guard let d = await callBridge("send", text) else { return nil }
        return SendResult(
            ok: (d["ok"] as? NSNumber)?.boolValue ?? false,
            clicked: (d["clicked"] as? NSNumber)?.boolValue ?? false,
            leftChars: (d["leftChars"] as? NSNumber)?.intValue ?? 0
        )
    }

    public func pressEnterFallback() async -> Bool {
        guard let d = await callBridge("pressEnter") else { return false }
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
        guard let d = await callBridge("collect") else { return nil }
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
        _ = await callBridge("stop")
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
}
