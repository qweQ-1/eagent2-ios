import XCTest
@testable import EAgent2

final class ToolRouterTests: XCTestCase {

    var root: URL!

    override func setUp() {
        super.setUp()
        root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("eagent-test-\(UUID().uuidString)")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: root)
        super.tearDown()
    }

    @MainActor
    private func makeRouter() -> ToolRouter {
        ToolRouter(workspaceURL: root)
    }

    // MARK: 路径安全

    func testResolveNormal() {
        XCTAssertEqual(FilesTool.resolve("a/b.txt", root: root)?.lastPathComponent, "b.txt")
        XCTAssertEqual(FilesTool.resolve("/a/b.txt", root: root)?.lastPathComponent, "b.txt")
        XCTAssertEqual(FilesTool.resolve("workspace/a.txt", root: root)?.lastPathComponent, "a.txt")
    }

    func testResolveTraversalRejected() {
        XCTAssertNil(FilesTool.resolve("../etc/passwd", root: root))
        XCTAssertNil(FilesTool.resolve("../../../../etc/passwd", root: root))
        XCTAssertNil(FilesTool.resolve("workspace/../../etc/passwd", root: root))
        XCTAssertNil(FilesTool.resolve("/etc/passwd", root: root))
    }

    func testDisplayRelative() {
        let f = root.appendingPathComponent("sub/x.txt")
        XCTAssertEqual(FilesTool.display(f, root: root), "/sub/x.txt")
        XCTAssertEqual(FilesTool.display(root, root: root), "/")
    }

    // MARK: 文件读写

    func testWriteReadRoundTrip() {
        let w = FilesTool.write(root: root, path: "notes/hello.txt", content: "你好 EAgent")
        XCTAssertTrue(w.contains("\"ok\":true"))
        let r = FilesTool.read(root: root, path: "notes/hello.txt")
        XCTAssertTrue(r.contains("你好 EAgent"))
        let l = FilesTool.list(root: root, path: "/")
        XCTAssertTrue(l.contains("notes"))
    }

    func testReadMissing() {
        let r = FilesTool.read(root: root, path: "nope.txt")
        XCTAssertTrue(r.contains("\"ok\":false"))
    }

    func testReadTruncation() {
        _ = FilesTool.write(root: root, path: "big.txt", content: String(repeating: "x", count: 5000))
        let r = FilesTool.read(root: root, path: "big.txt", maxChars: 100)
        XCTAssertTrue(r.contains("\"truncated\":\"true\""))
        XCTAssertFalse(r.contains(String(repeating: "x", count: 101)))
    }

    // MARK: open 工具

    func testSafeURLAllowsHTTPS() {
        XCTAssertNotNil(OpenTool.safeURL("https://example.com/a?b=1"))
        XCTAssertNotNil(OpenTool.safeURL("weixin://"))
    }

    func testSafeURLBlocksDangerousSchemes() {
        XCTAssertNil(OpenTool.safeURL("javascript:alert(1)"))
        XCTAssertNil(OpenTool.safeURL("data:text/html,hi"))
        XCTAssertNil(OpenTool.safeURL("file:///etc/passwd"))
        XCTAssertNil(OpenTool.safeURL("about:blank"))
    }

    func testAliases() {
        XCTAssertEqual(OpenTool.schemeForApp("微信"), "weixin://")
        XCTAssertEqual(OpenTool.schemeForApp("支付宝"), "alipay://")
        XCTAssertNil(OpenTool.schemeForApp("不存在的AppXYZ"))
    }

    // MARK: http 工具

    func testBlockedHosts() {
        XCTAssertTrue(HTTPTool.isBlockedHost("localhost"))
        XCTAssertTrue(HTTPTool.isBlockedHost("127.0.0.1"))
        XCTAssertTrue(HTTPTool.isBlockedHost("10.1.2.3"))
        XCTAssertTrue(HTTPTool.isBlockedHost("192.168.1.1"))
        XCTAssertTrue(HTTPTool.isBlockedHost("172.16.0.9"))
        XCTAssertTrue(HTTPTool.isBlockedHost("172.31.255.255"))
        XCTAssertTrue(HTTPTool.isBlockedHost("169.254.1.1"))
        XCTAssertTrue(HTTPTool.isBlockedHost("router.local"))
        XCTAssertFalse(HTTPTool.isBlockedHost("172.32.0.1"))
        XCTAssertFalse(HTTPTool.isBlockedHost("api.open-meteo.com"))
        XCTAssertFalse(HTTPTool.isBlockedHost("chat.deepseek.com"))
    }

    func testMakeRequestGuard() {
        switch HTTPTool.makeRequest(urlString: "http://example.com", method: "GET", body: nil, headers: [:]) {
        case .success: XCTFail("http 应被拒绝")
        case .failure(let e): XCTAssertTrue(e.contains("https"))
        }
        switch HTTPTool.makeRequest(urlString: "https://127.0.0.1/x", method: "GET", body: nil, headers: [:]) {
        case .success: XCTFail("内网应被拒绝")
        case .failure(let e): XCTAssertTrue(e.contains("内网"))
        }
        switch HTTPTool.makeRequest(urlString: "https://example.com/a", method: "PATCH", body: "{}", headers: ["X-A": "b"]) {
        case .success(let req):
            XCTAssertEqual(req.httpMethod, "GET") // 非白名单方法回退 GET
            XCTAssertEqual(req.value(forHTTPHeaderField: "X-A"), "b")
            XCTAssertEqual(String(data: req.httpBody!, encoding: .utf8), "{}")
        case .failure(let e): XCTFail(e)
        }
    }

    func testParseHeaders() {
        XCTAssertEqual(ToolRouter.parseHeaders("{\"A\":\"b\"}"), ["A": "b"])
        XCTAssertEqual(ToolRouter.parseHeaders("not-json"), [:])
        XCTAssertEqual(ToolRouter.parseHeaders(nil), [:])
    }

    // MARK: 路由

    @MainActor
    func testUnknownToolError() async {
        let r = await makeRouter().call(ToolCall(tool: "rm_rf", args: [:]))
        XCTAssertTrue(r.contains("未知工具"))
        XCTAssertTrue(r.contains("list_tools"))
    }

    @MainActor
    func testListTools() async {
        let r = await makeRouter().call(ToolCall(tool: "list_tools"))
        XCTAssertTrue(r.contains("\"ok\":true"))
        for n in ToolCatalog.names { XCTAssertTrue(r.contains(n), "list_tools 缺少 \(n)") }
    }

    @MainActor
    func testMissingArgError() async {
        let r = await makeRouter().call(ToolCall(tool: "open_app", args: [:]))
        XCTAssertTrue(r.contains("\"ok\":false"))
        XCTAssertTrue(r.contains("name"))
    }

    @MainActor
    func testFinishMarker() async {
        let r = await makeRouter().call(ToolCall(tool: "finish", args: ["note": "已完成"]))
        XCTAssertTrue(r.contains("\"finish\":\"true\""))
    }

    @MainActor
    func testRouteFiles() async {
        let router = makeRouter()
        let w = await router.call(ToolCall(tool: "write_file", args: ["path": "via/router.txt", "content": "路由写入"]))
        XCTAssertTrue(w.contains("\"ok\":true"))
        let r = await router.call(ToolCall(tool: "read_file", args: ["path": "via/router.txt"]))
        XCTAssertTrue(r.contains("路由写入"))
    }
}
