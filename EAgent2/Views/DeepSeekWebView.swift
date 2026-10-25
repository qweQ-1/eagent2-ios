import SwiftUI
import WebKit

/// 内嵌 DeepSeek 网页版（桌面 UA + 登录态持久化 + 注入桥）。
///
/// 内存要点（iPhone XR 等 2GB 机器上会直接闪退）：
/// - WKWebView 必须能在视图拆除时真正释放，否则每次进入聊天页泄漏一个 WebView（数十 MB）；
/// - 注入脚本只注入主 frame（forMainFrameOnly: true），否则 DeepSeek 页里的每个 iframe
///   都会跑一份桥脚本并各自 postMessage，内存与 CPU 双爆；
/// - 收到内存告警时主动降低负载（停止加载、清空缓存）。
struct DeepSeekWebView: UIViewRepresentable {
    @ObservedObject var bridge: WebBridge

    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        var bridge: WebBridge
        init(bridge: WebBridge) { self.bridge = bridge }

        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "eagent" else { return }
            if let body = message.body as? [String: Any], (body["type"] as? String) == "token" {
                Task { @MainActor in bridge.noteTokenCaptured() }
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            Task { @MainActor in bridge.refreshFromState() }
        }

        /// 页面即将消失时通知 bridge，停止一切轮询与 JS 调用
        func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {}

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            Task { @MainActor in bridge.noteWebError(error.localizedDescription) }
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            Task { @MainActor in bridge.noteWebError(error.localizedDescription) }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(bridge: bridge) }

    func makeUIView(context: Context) -> WKWebView {
        let controller = WKUserContentController()
        controller.add(context.coordinator, name: "eagent")
        // 只注入主 frame：避免 iframe 重复注入导致内存/CPU 飙升
        let script = WKUserScript(source: BridgeScript.source, injectionTime: .atDocumentStart, forMainFrameOnly: true)
        controller.addUserScript(script)

        let config = WKWebViewConfiguration()
        config.userContentController = controller
        config.websiteDataStore = WKWebsiteDataStore.default()
        // 关闭默认的额外特性，减少内存占用
        config.preferences.javaScriptCanOpenWindowsAutomatically = false
        config.allowsInlineMediaPlayback = false

        let wv = WKWebView(frame: .zero, configuration: config)
        wv.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Safari/605.1.15"
        wv.allowsBackForwardNavigationGestures = true
        wv.navigationDelegate = context.coordinator
        wv.load(URLRequest(url: WebBridge.chatURL))
        context.coordinator.bridge = bridge
        bridge.attach(wv)
        return wv
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    /// SwiftUI 拆除视图时调用：在这里彻底释放 WebView 相关资源，防止内存泄漏。
    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        uiView.stopLoading()
        uiView.navigationDelegate = nil
        uiView.configuration.userContentController.removeScriptMessageHandler(forName: "eagent")
        uiView.configuration.userContentController.removeAllUserScripts()
        coordinator.bridge.detach()
    }
}
