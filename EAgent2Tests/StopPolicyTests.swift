import XCTest
@testable import EAgent2

/// 自动截停判定的测试。
final class StopPolicyTests: XCTestCase {

    // MARK: 无法完成

    func testDetectsImpossible() {
        XCTAssertTrue(StopPolicy.looksImpossible("我无法访问你的相册"))
        XCTAssertTrue(StopPolicy.looksImpossible("抱歉，我没有权限执行这个操作"))
        XCTAssertTrue(StopPolicy.looksImpossible("无法连接到该服务器"))
        XCTAssertTrue(StopPolicy.looksImpossible("请提供更多信息以便我继续"))
        XCTAssertTrue(StopPolicy.looksImpossible("这个功能暂时不支持"))
    }

    func testNormalReplyIsNotImpossible() {
        XCTAssertFalse(StopPolicy.looksImpossible("好的，我已经帮你创建了明天上午 9 点的提醒。"))
        XCTAssertFalse(StopPolicy.looksImpossible("任务完成，通知已发送。"))
        XCTAssertFalse(StopPolicy.looksImpossible(""))
    }

    // MARK: 无实质进展

    func testDetectsIdle() {
        XCTAssertTrue(StopPolicy.looksIdle(""))
        XCTAssertTrue(StopPolicy.looksIdle("   "))
        XCTAssertTrue(StopPolicy.looksIdle("好的"))
        XCTAssertTrue(StopPolicy.looksIdle("你好"))
        XCTAssertTrue(StopPolicy.looksIdle("ok！"))
    }

    func testSubstantiveReplyIsNotIdle() {
        XCTAssertFalse(StopPolicy.looksIdle("已经为你创建了提醒事项，明天上午 9 点，标题是开会。"))
        XCTAssertFalse(StopPolicy.looksIdle("我调用了 write_file 工具，写入了一个文件。"))
    }

    // MARK: 工具结果失败

    func testFailedResultDetection() {
        XCTAssertTrue(StopPolicy.isFailedResult("{\"ok\":\"false\",\"error\":\"文件不存在\"}"))
        XCTAssertFalse(StopPolicy.isFailedResult("{\"ok\":\"true\",\"content\":\"hello\"}"))
        XCTAssertFalse(StopPolicy.isFailedResult("这不是 JSON"))
    }

    // MARK: 连续失败熔断

    func testFailureStreakThreshold() {
        XCTAssertTrue(StopPolicy.shouldPauseOnFailure(tool: "speak", streak: 3, threshold: 3))
        XCTAssertFalse(StopPolicy.shouldPauseOnFailure(tool: "speak", streak: 2, threshold: 3))
        XCTAssertFalse(StopPolicy.shouldPauseOnFailure(tool: "speak", streak: 9, threshold: 0))
    }

    // MARK: StopReason

    func testStopReasonMetadata() {
        XCTAssertTrue(StopReason.completed.isPause)
        XCTAssertTrue(StopReason.impossible.isPause)
        XCTAssertTrue(StopReason.idle.isPause)
        XCTAssertTrue(StopReason.maxRounds.isPause)
        XCTAssertTrue(StopReason.timeout.isPause)
        XCTAssertFalse(StopReason.repeatedFailure(tool: "x", count: 3).isPause)
        XCTAssertFalse(StopReason.userStopped.isPause)
        XCTAssertEqual(StopReason.impossible.title, "无法完成")
    }
}
