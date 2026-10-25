import Foundation

/// 受限 HTTP 请求：仅 https，禁止内网/本机地址，响应截断。
public enum HTTPTool {

    public static func isBlockedHost(_ host: String) -> Bool {
        let h = host.lowercased()
        if h == "localhost" || h.hasSuffix(".localhost") { return true }
        if h == "127.0.0.1" || h == "0.0.0.0" || h == "::1" { return true }
        if h.hasPrefix("10.") || h.hasPrefix("192.168.") || h.hasPrefix("169.254.") { return true }
        if h.hasPrefix("172.") {
            let parts = h.split(separator: ".").compactMap { Int($0) }
            if parts.count >= 2, parts[0] == 172, parts[1] >= 16, parts[1] <= 31 { return true }
        }
        // .local / .internal / 无点的裸主机名
        if h.hasSuffix(".local") || h.hasSuffix(".internal") || !h.contains(".") { return true }
        return false
    }

    /// 构造请求失败时的错误（携带可读信息）
    public struct Failure: Error, CustomStringConvertible {
        public let message: String
        public init(_ message: String) { self.message = message }
        public var description: String { message }
    }

    /// 构造 & 校验请求；返回错误信息或请求。
    public static func makeRequest(urlString: String, method: String, body: String?, headers: [String: String]) -> Result<URLRequest, Failure> {
        guard let url = URL(string: urlString.trimmingCharacters(in: .whitespaces)) else {
            return .failure(Failure("URL 不合法"))
        }
        guard let scheme = url.scheme?.lowercased(), scheme == "https" else {
            return .failure(Failure("仅允许 https 请求"))
        }
        guard let host = url.host, !host.isEmpty else { return .failure(Failure("缺少主机名")) }
        if isBlockedHost(host) { return .failure(Failure("禁止访问内网/本机地址：" + host)) }
        var req = URLRequest(url: url, timeoutInterval: 15)
        let m = method.trimmingCharacters(in: .whitespaces).uppercased()
        req.httpMethod = (m == "GET" || m == "POST" || m == "PUT" || m == "DELETE") ? m : "GET"
        req.httpBody = body.map { Data($0.utf8) }
        if req.httpBody != nil { req.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        for (k, v) in headers {
            let kk = k.trimmingCharacters(in: .whitespaces)
            if !kk.isEmpty { req.setValue(v, forHTTPHeaderField: kk) }
        }
        req.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) EAgent/1.0", forHTTPHeaderField: "User-Agent")
        return .success(req)
    }

    @MainActor
    public static func run(url: String, method: String, body: String?, headers: [String: String], maxChars: Int = 8000) async -> String {
        var req: URLRequest
        switch makeRequest(urlString: url, method: method, body: body, headers: headers) {
        case .failure(let e): return FilesTool.err(e)
        case .success(let r): req = r
        }
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
            var text = String(decoding: data, as: UTF8.self)
            var truncated = false
            if text.count > maxChars { text = String(text.prefix(maxChars)); truncated = true }
            return FilesTool.ok(["status": String(code), "truncated": truncated ? "true" : "false", "body": text])
        } catch {
            return FilesTool.err("请求失败：" + error.localizedDescription)
        }
    }
}
