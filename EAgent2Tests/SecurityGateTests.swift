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
}
