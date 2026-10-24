import XCTest
@testable import EAgent2

final class ToolCallCodecTests: XCTestCase {

    func testFencedBlock() {
        let text = "好的，我先看一下你的工作区。\n```eagent\n{\"tool\":\"list_files\",\"args\":{\"path\":\"/\"},\"note\":\"看看有哪些文件\"}\n```\n还需要一点时间。"
        let r = ToolCallCodec.parse(from: text)
        guard case .found(let call) = r else { return XCTFail("期望 found，实际 \(r)") }
        XCTAssertEqual(call.tool, "list_files")
        XCTAssertEqual(call.args["path"], "/")
        XCTAssertEqual(call.note, "看看有哪些文件")
    }

    func testBareJSONFallback() {
        let r = ToolCallCodec.parse(from: "我先帮你打开：{\"tool\":\"open_app\",\"args\":{\"name\":\"微信\"}}")
        guard case .found(let call) = r else { return XCTFail("期望 found，实际 \(r)") }
        XCTAssertEqual(call.tool, "open_app")
        XCTAssertEqual(call.args["name"], "微信")
    }

    func testNoCall() {
        XCTAssertEqual(ToolCallCodec.parse(from: "好的，已经帮你弄好了，随时告诉我。"), .none)
        XCTAssertEqual(ToolCallCodec.parse(from: "   "), .none)
    }

    func testMalformedJSON() {
        let r = ToolCallCodec.parse(from: "```eagent\n{\"tool\": \"open_app\", oops}\n```")
        guard case .malformed(let why) = r else { return XCTFail("期望 malformed，实际 \(r)") }
        XCTAssertTrue(why.contains("JSON"))
    }

    func testMissingToolField() {
        let r = ToolCallCodec.parse(from: "```eagent\n{\"args\":{\"path\":\"/\"}}\n```")
        guard case .malformed(let why) = r else { return XCTFail("期望 malformed，实际 \(r)") }
        XCTAssertTrue(why.contains("tool"))
    }

    func testMultipleBlocksTakesFirst() {
        let text = "```eagent\n{\"tool\":\"read_file\",\"args\":{\"path\":\"a.txt\"}}\n```\n```eagent\n{\"tool\":\"speak\",\"args\":{\"text\":\"hi\"}}\n```"
        guard case .found(let call) = ToolCallCodec.parse(from: text) else { return XCTFail("期望 found") }
        XCTAssertEqual(call.tool, "read_file")
    }

    func testNestedBracesAndBracesInStrings() {
        let text = "```eagent\n{\"tool\":\"write_file\",\"args\":{\"path\":\"x.json\",\"content\":\"{\\\"a\\\": 1}\"},\"note\":\"含 }\`\` 字符串\"}\n```"
        guard case .found(let call) = ToolCallCodec.parse(from: text) else { return XCTFail("期望 found，实际: \(ToolCallCodec.parse(from: text))") }
        XCTAssertEqual(call.tool, "write_file")
        XCTAssertEqual(call.args["content"], "{\"a\": 1}")
    }

    func testNumberAndBoolCoercion() {
        let r = ToolCallCodec.parse(from: "{\"tool\":\"http_request\",\"args\":{\"method\":\"GET\",\"follow\":true,\"retry\":3}}")
        guard case .found(let call) = r else { return XCTFail("期望 found，实际 \(r)") }
        XCTAssertEqual(call.args["follow"], "true")
        XCTAssertEqual(call.args["retry"], "3")
    }

    func testEncodeRoundTrip() {
        let call = ToolCall(tool: "speak", args: ["text": "你好，引用 {\"x\":1}", "rate": "1.0"], note: "测试")
        let encoded = ToolCallCodec.encode(call)
        guard case .found(let back) = ToolCallCodec.parse(from: encoded) else { return XCTFail("roundtrip 失败") }
        XCTAssertEqual(back.tool, call.tool)
        XCTAssertEqual(back.args["text"], call.args["text"])
        XCTAssertEqual(back.note, call.note)
    }

    func testBalancedScannerIgnoresStrings() {
        let s = "prefix {\"tool\":\"x\",\"args\":{\"content\":\"}{\"}}\" } suffix"
        let obj = ToolCallCodec.firstBalancedJSONObject(in: s)
        XCTAssertEqual(obj, "{\"tool\":\"x\",\"args\":{\"content\":\"}{\"}}\" }")
    }

    func testBalancedScannerReturnsNilOnUnbalanced() {
        XCTAssertNil(ToolCallCodec.firstBalancedJSONObject(in: "abc {\"tool\": no close"))
    }
}
