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

    @MainActor
    func testGateResolveSequential() async {
        let gate = SecurityGate()
        let first = Task { @MainActor in await gate.request(tool: "speak", note: nil, args: ["text": "hi"], index: 1, total: 5) }
        // 等一下让 pending 出现
        for _ in 0..<50 where gate.pending == nil { try? await Task.sleep(nanoseconds: 20_000_000) }
        XCTAssertNotNil(gate.pending)
        gate.resolve(.run)
        let d = await first.value
        XCTAssertEqual(d, .run)
        XCTAssertNil(gate.pending)
    }

    /// 重复 resolve 不能重复 resume 同一个 continuation（否则 Swift 运行时直接 fatalError 崩溃）。
    @MainActor
    func testGateResolveIsIdempotent() async {
        let gate = SecurityGate()
        let t = Task { @MainActor in await gate.request(tool: "speak", note: nil, args: [:], index: 1, total: 5) }
        for _ in 0..<50 where gate.pending == nil { try? await Task.sleep(nanoseconds: 20_000_000) }
        gate.resolve(.run)
        gate.resolve(.skip)   // 第二次必须无副作用
        gate.resolve(.abort)
        let d = await t.value
        XCTAssertEqual(d, .run)
    }

    /// 上一次请求未收尾就发起新请求：旧请求应被安全地 abort，不能让 continuation 泄漏。
    @MainActor
    func testGateSecondRequestAbortsFirst() async {
        let gate = SecurityGate()
        let first = Task { @MainActor in await gate.request(tool: "a", note: nil, args: [:], index: 1, total: 5) }
        for _ in 0..<50 where gate.pending == nil { try? await Task.sleep(nanoseconds: 20_000_000) }
        let second = Task { @MainActor in await gate.request(tool: "b", note: nil, args: [:], index: 2, total: 5) }
        for _ in 0..<50 where gate.pending == nil { try? await Task.sleep(nanoseconds: 20_000_000) }
        gate.resolve(.run)
        let d1 = await first.value
        let d2 = await second.value
        XCTAssertEqual(d1, .abort)
        XCTAssertEqual(d2, .run)
    }
}
