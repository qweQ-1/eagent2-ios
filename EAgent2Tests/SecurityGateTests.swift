import XCTest
@testable import EAgent2

final class SecurityGateTests: XCTestCase {

    func testPolicyUserWins() {
        XCTAssertEqual(GatePolicy.resolve(timeoutFired: true, user: .skip, timeoutRuns: true), .skip)
        XCTAssertEqual(GatePolicy.resolve(timeoutFired: true, user: .run, timeoutRuns: false), .run)
    }

    func testPolicyTimeout() {
        XCTAssertEqual(GatePolicy.resolve(timeoutFired: true, user: nil, timeoutRuns: true), .run)
        XCTAssertEqual(GatePolicy.resolve(timeoutFired: true, user: nil, timeoutRuns: false), .skip)
    }

    func testPolicyNoTimeoutNoUser() {
        XCTAssertEqual(GatePolicy.resolve(timeoutFired: false, user: nil, timeoutRuns: true), .skip)
    }

    func testPrettyArgs() {
        let s = SecurityGate.prettyArgs(["b": "2", "a": "1", "note": "中文"])
        XCTAssertEqual(s, "a: 1\nb: 2\nnote: 中文")
        XCTAssertEqual(SecurityGate.prettyArgs([:]), "（无参数）")
    }

    // MARK: - 辅助

    /// 等待安全门挂起某个工具的审批请求。
    ///
    /// 用 pending.tool 作为「continuation 已注册」的可靠信号：
    /// request() 里设置 pending 与注册 continuation 之间没有 await 点，不会被打断，
    /// 因此观察到 pending.tool == tool 就意味着 continuation 已经就绪。
    @MainActor
    private func waitForPending(_ gate: SecurityGate, tool: String, timeout: TimeInterval = 3) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if gate.pending?.tool == tool { return true }
            try? await Task.sleep(nanoseconds: 2_000_000)
        }
        return gate.pending?.tool == tool
    }

    // MARK: - 行为

    @MainActor
    func testGateResolveSequential() async {
        let gate = SecurityGate()
        let exp = expectation(description: "gate resolved")
        var got: GateDecision?
        Task { @MainActor in
            got = await gate.request(tool: "speak", note: nil, args: ["text": "hi"], index: 1, total: 5)
            exp.fulfill()
        }
        let ready = await waitForPending(gate, tool: "speak")
        XCTAssertTrue(ready)
        gate.resolve(.run)
        await fulfillment(of: [exp], timeout: 5)
        XCTAssertEqual(got, .run)
        XCTAssertNil(gate.pending)
    }

    /// 重复 resolve 不能重复 resume 同一个 continuation（否则 Swift 运行时直接 fatalError 崩溃）。
    @MainActor
    func testGateResolveIsIdempotent() async {
        let gate = SecurityGate()
        let exp = expectation(description: "gate resolved")
        var got: GateDecision?
        Task { @MainActor in
            got = await gate.request(tool: "speak", note: nil, args: [:], index: 1, total: 5)
            exp.fulfill()
        }
        let ready = await waitForPending(gate, tool: "speak")
        XCTAssertTrue(ready)
        gate.resolve(.run)
        gate.resolve(.skip)   // 第二次必须无副作用
        gate.resolve(.abort)
        await fulfillment(of: [exp], timeout: 5)
        XCTAssertEqual(got, .run)
    }

    /// 上一次请求未收尾就发起新请求：旧请求应被安全地 abort，不能让 continuation 泄漏。
    @MainActor
    func testGateSecondRequestAbortsFirst() async {
        let gate = SecurityGate()
        let exp1 = expectation(description: "first resolved")
        let exp2 = expectation(description: "second resolved")
        var got1: GateDecision?
        var got2: GateDecision?
        Task { @MainActor in
            got1 = await gate.request(tool: "first", note: nil, args: [:], index: 1, total: 5)
            exp1.fulfill()
        }
        let ready1 = await waitForPending(gate, tool: "first")
        XCTAssertTrue(ready1)
        Task { @MainActor in
            got2 = await gate.request(tool: "second", note: nil, args: [:], index: 2, total: 5)
            exp2.fulfill()
        }
        // 等到第二次请求接管 pending，说明第一个 continuation 已被 abort
        let ready2 = await waitForPending(gate, tool: "second")
        XCTAssertTrue(ready2)
        gate.resolve(.run)
        await fulfillment(of: [exp1, exp2], timeout: 5)
        XCTAssertEqual(got1, .abort)
        XCTAssertEqual(got2, .run)
    }
}
