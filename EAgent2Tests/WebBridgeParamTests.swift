import XCTest
@testable import EAgent2

/// WebBridge 的纯逻辑测试（不依赖 WebView）。
final class WebBridgeParamTests: XCTestCase {

    /// 把字符串编码成可安全嵌入 JS 表达式的 JSON 字面量。
    /// 与 WebBridge.jsonLiteral 保持一致。
    private func jsonLiteral(_ s: String) -> String? {
        guard let data = try? JSONSerialization.data(withJSONObject: [s]),
              let arr = String(data: data, encoding: .utf8),
              arr.hasPrefix("["), arr.hasSuffix("]") else { return nil }
        return String(arr.dropFirst().dropLast())
    }

    func testPlainText() {
        XCTAssertEqual(jsonLiteral("你好"), "\"你好\"")
    }

    func testEscapesQuotes() {
        let lit = jsonLiteral("say \"hi\"")
        XCTAssertNotNil(lit)
        XCTAssertTrue(lit!.contains("\\\""))
        // 反解回来必须与原文一致
        let data = "[\(lit!)]".data(using: .utf8)!
        let arr = try! JSONSerialization.jsonObject(with: data) as! [String]
        XCTAssertEqual(arr.first, "say \"hi\"")
    }

    func testEscapesNewlineAndTab() {
        let lit = jsonLiteral("a\nb\tc")
        let data = "[\(lit!)]".data(using: .utf8)!
        let arr = try! JSONSerialization.jsonObject(with: data) as! [String]
        XCTAssertEqual(arr.first, "a\nb\tc")
    }

    func testEscapesBackslash() {
        let lit = jsonLiteral("back\\slash")
        let data = "[\(lit!)]".data(using: .utf8)!
        let arr = try! JSONSerialization.jsonObject(with: data) as! [String]
        XCTAssertEqual(arr.first, "back\\slash")
    }

    /// 关键回归测试：历史上因为参数传递方式错误，把字符串 "undefined" 填进了输入框。
    func testLiteralUndefinedStaysQuoted() {
        let lit = jsonLiteral("undefined")
        XCTAssertEqual(lit, "\"undefined\"")
    }

    func testEmptyString() {
        let lit = jsonLiteral("")
        XCTAssertEqual(lit, "\"\"")
    }

    func testLongText() {
        let s = String(repeating: "长", count: 1000)
        let lit = jsonLiteral(s)
        let data = "[\(lit!)]".data(using: .utf8)!
        let arr = try! JSONSerialization.jsonObject(with: data) as! [String]
        XCTAssertEqual(arr.first?.count, 1000)
    }

    /// 注入脚本里不能出现会提前结束 Swift raw string 的序列。
    func testBridgeScriptHasNoRawStringBreakers() {
        XCTAssertFalse(BridgeScript.source.contains(#"\"#""#))
        XCTAssertFalse(BridgeScript.source.contains(#"\#(""#))
    }

    /// 注入脚本必须包含参数提取逻辑，且不能退化成直接使用 arguments.payload。
    func testBridgeScriptUsesPickText() {
        XCTAssertTrue(BridgeScript.source.contains("function pickText"))
        XCTAssertTrue(BridgeScript.source.contains("var text = pickText(arg)"))
    }
}
