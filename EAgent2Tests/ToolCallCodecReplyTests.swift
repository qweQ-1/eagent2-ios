import XCTest
@testable import EAgent2

/// 工具块解析的回归测试。
/// 历史 bug：把「我们自己发出去的系统提示词」当成 DeepSeek 的回复，
/// 导致从提示词示例里解析出 {"tool":"工具名"} → 工具名无效 → 「工具用不了」。
final class ToolCallCodecReplyTests: XCTestCase {

    /// 提示词里的示例块（会被误读的那段）
    private let promptExample = """
    【输出协议（必须严格遵守）】
    1. 需要操控手机时，你的整个回复中必须只包含一个代码块，语言标记固定为 eagent：
    ```eagent
    {"tool":"工具名","args":{"参数名":"参数值"},"note":"一句话说明你要做什么"}
    ```
    """

    func testParsesRealFencedBlock() {
        let reply = """
        好的，我先帮你发个通知。
        ```eagent
        {"tool":"notify","args":{"title":"测试"},"note":"发通知"}
        ```
        """
        guard case .found(let call) = ToolCallCodec.parse(from: reply) else {
            return XCTFail("应解析出工具调用")
        }
        XCTAssertEqual(call.tool, "notify")
        XCTAssertEqual(call.args["title"], "测试")
    }

    /// 关键回归：从「正文在前、工具块在后」的消息里取到的是后面的真工具块。
    func testPrefersLastJSONObject() {
        let reply = promptExample + "\n\n```eagent\n{\"tool\":\"speak\",\"args\":{\"text\":\"你好\"}}\n```"
        guard case .found(let call) = ToolCallCodec.parse(from: reply) else {
            return XCTFail("应解析出工具调用")
        }
        XCTAssertEqual(call.tool, "speak", "应取到最后的 JSON，而不是提示词里的示例")
    }

    func testLastBalancedJSONObjectPicksLast() {
        let text = "前缀 {\"tool\":\"a\"} 中间 {\"tool\":\"b\"} 结尾"
        let last = ToolCallCodec.lastBalancedJSONObject(in: text)
        XCTAssertEqual(last, "{\"tool\":\"b\"}")
    }

    func testLastBalancedJSONObjectIgnoresBracesInStrings() {
        let text = "{\"tool\":\"x\",\"args\":{\"content\":\"}{\"}}"
        let last = ToolCallCodec.lastBalancedJSONObject(in: text)
        XCTAssertNotNil(last)
        XCTAssertTrue(last!.contains("\"tool\":\"x\""))
    }

    func testLastBalancedJSONObjectNilWhenNoObject() {
        XCTAssertNil(ToolCallCodec.lastBalancedJSONObject(in: "没有任何花括号"))
    }

    /// 工具名不在目录里 → 引擎层会拒绝，这里确认目录本身是完备的。
    func testCatalogContainsCoreTools() {
        for name in ["notify", "speak", "write_file", "read_file", "open_app", "finish"] {
            XCTAssertTrue(ToolCatalog.names.contains(name), "目录缺少 \(name)")
        }
    }
}
