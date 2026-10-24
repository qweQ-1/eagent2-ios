import XCTest
@testable import EAgent2

final class PromptBuilderTests: XCTestCase {

    private let specs = ToolRouter.specs

    func testSystemPromptContainsAllTools() {
        let p = PromptBuilder.systemPrompt(workspacePath: "/var/x/workspace", tools: specs, deviceLine: "device-line")
        for s in specs {
            XCTAssertTrue(p.contains(s.name), "系统提示词缺少工具 \(s.name)")
        }
    }

    func testSystemPromptContainsEnvironment() {
        let p = PromptBuilder.systemPrompt(workspacePath: "/var/x/workspace", tools: specs, deviceLine: "device-line")
        XCTAssertTrue(p.contains("/var/x/workspace"))
        XCTAssertTrue(p.contains("device-line"))
        XCTAssertTrue(p.contains("eagent"))
        XCTAssertTrue(p.contains("每个回复最多输出一个 eagent 工具块"))
    }

    func testTaskMessageMerges() {
        let sys = "【系统】ABC"
        let msg = PromptBuilder.taskMessage(userTask: "帮我打开微信", systemPrompt: sys)
        XCTAssertTrue(msg.hasPrefix("【系统】ABC"))
        XCTAssertTrue(msg.contains("【用户任务】"))
        XCTAssertTrue(msg.contains("帮我打开微信"))
    }

    func testFeedMessage() {
        let m = PromptBuilder.feedMessage(tool: "open_app", result: "{\"ok\":true}")
        XCTAssertTrue(m.contains("【工具结果 open_app】"))
        XCTAssertTrue(m.contains("ok"))
        XCTAssertTrue(m.contains("eagent"))
    }

    func testMalformedMessage() {
        let m = PromptBuilder.malformedMessage("eagent 块不是合法 JSON", lastOutput: "{\"tool\":")
        XCTAssertTrue(m.contains("eagent 块不是合法 JSON"))
        XCTAssertTrue(m.contains("{\"tool\":"))
    }

    func testDisabledToolExcluded() {
        let subset = specs.filter { $0.name != "http_request" }
        let p = PromptBuilder.systemPrompt(workspacePath: "/w", tools: subset, deviceLine: "d")
        XCTAssertFalse(p.contains("http_request"))
        XCTAssertTrue(p.contains("speak"))
    }
}
