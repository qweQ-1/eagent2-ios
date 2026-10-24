import SwiftUI
import WebKit

/// 内嵌 DeepSeek 网页版（桌面 UA + 登录态持久化 + 注入桥）。
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
    }

    func makeCoordinator() -> Coordinator { Coordinator(bridge: bridge) }

    func makeUIView(context: Context) -> WKWebView {
        let controller = WKUserContentController()
        controller.add(context.coordinator, name: "eagent")
        let script = WKUserScript(source: BridgeScript.source, injectionTime: .atDocumentStart, forMainFrameOnly: false)
        controller.addUserScript(script)

        let config = WKWebViewConfiguration()
        config.userContentController = controller
        config.websiteDataStore = WKWebsiteDataStore.default()

        let wv = WKWebView(frame: .zero, configuration: config)
        wv.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Safari/605.1.15"
        wv.allowsBackForwardNavigationGestures = true
        wv.navigationDelegate = context.coordinator
        wv.load(URLRequest(url: WebBridge.chatURL))
        context.coordinator.bridge = bridge
        Task { @MainActor in bridge.attach(wv) }
        return wv
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
