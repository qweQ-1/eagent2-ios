import Foundation
import UIKit

/// 打开 App / URL。打开外部链接对应用户可见动作，等价于 PC 版「让 AI 帮你点开某个程序」。
public enum OpenTool {

    /// 常用 App 别名 → URL Scheme。
    public static let appAliases: [String: String] = [
        "微信": "weixin://",
        "wechat": "weixin://",
        "支付宝": "alipay://",
        "alipay": "alipay://",
        "淘宝": "taobao://",
        "taobao": "taobao://",
        "qq": "mqq://",
        "QQ": "mqq://",
        "微博": "sinaweibo://",
        "weibo": "sinaweibo://",
        "抖音": "snssdk1128://",
        "douyin": "snssdk1128://",
        "拼多多": "pinduoduo://",
        "高德地图": "iosamap://",
        "百度地图": "baidumap://",
        "设置": "App-Prefs:root=WIFI", // iOS 16+ 深链设置（失败时退回 prefs:root）
        "settings": "App-Prefs:root=WIFI",
        "照片": "photos-redirect://",
        "地图": "maps://",
        "maps": "maps://",
        "快捷指令": "shortcuts://",
        "shortcuts": "shortcuts://",
        "appstore": "itms-apps://",
        "AppStore": "itms-apps://",
        "时钟": "clock-alarm://"
    ]

    public static func schemeForApp(_ name: String) -> String? {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if let direct = appAliases[n] { return direct }
        // 去空格/「app」后缀再试
        let flat = n.replacingOccurrences(of: " ", with: "").lowercased()
        for (k, v) in appAliases where k.lowercased() == flat { return v }
        if let v = appAliases[flat] { return v }
        return nil
    }

    /// 只允许 http/https 与已知安全 scheme；拦截 javascript:/data:/file: 等。
    public static func safeURL(_ raw: String) -> URL? {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }
        guard let url = URL(string: s) else { return nil }
        let scheme = (url.scheme ?? "").lowercased()
        let blocked: Set<String> = ["javascript", "data", "file", "about", "blob"]
        if blocked.contains(scheme) { return nil }
        guard scheme == "http" || scheme == "https" || scheme.count >= 3 else { return nil }
        // 自定义 scheme 只放行已在别名表或常见注册过的（保守：只放行别名表里出现过的 scheme + http/https）
        if scheme == "http" || scheme == "https" { return url }
        let knownSchemes = Set(OpenTool.appAliases.values.compactMap { URL(string: $0)?.scheme })
        guard knownSchemes.contains(scheme) else { return nil }
        return url
    }

    @MainActor
    public static func open(url: URL) async -> String {
        await withCheckedContinuation { cont in
            UIApplication.shared.open(url, options: [:]) { ok in
                cont.resume(returning: ok
                    ? FilesTool.ok(["opened": url.absoluteString])
                    : FilesTool.err("系统拒绝打开或未安装对应 App：" + url.absoluteString))
            }
        }
    }

    /// 别名不在表里时，退回系统搜索网页（让用户自己挑）
    public static func fallbackSearch(_ name: String) -> URL? {
        let q = name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        return URL(string: "https://www.bing.com/search?q=" + q + "%20app%20store")
    }
}
