import XCTest
@testable import EAgent2

final class NaturalDateTests: XCTestCase {

    var now: Date!
    var tz: TimeZone!
    var cal: Calendar!

    override func setUp() {
        super.setUp()
        tz = TimeZone(identifier: "Asia/Shanghai")!
        cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        var comps = DateComponents()
        comps.year = 2026; comps.month = 10; comps.day = 24; comps.hour = 9; comps.minute = 0
        now = cal.date(from: comps)!
    }

    private func assert(_ d: Date?, _ ymd: String, _ hm: String, file: StaticString = #filePath, line: UInt = #line) {
        guard let d = d else { XCTFail("解析结果为 nil", file: file, line: line); return }
        let f = DateFormatter()
        f.timeZone = tz; f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm"
        XCTAssertEqual(f.string(from: d), ymd + " " + hm, file: file, line: line)
    }

    func testMorrowMorning() { assert(NaturalDate.parse("明天上午9点", now: now, timeZone: tz), "2026-10-25", "09:00") }
    func testMorrowEveningHalf() { assert(NaturalDate.parse("明天晚上8点半", now: now, timeZone: tz), "2026-10-25", "20:30") }
    func testDayAfterTomorrowPM() { assert(NaturalDate.parse("后天下午3点", now: now, timeZone: tz), "2026-10-26", "15:00") }
    func testRelativeMinutes() { assert(NaturalDate.parse("30分钟后", now: now, timeZone: tz), "2026-10-24", "09:30") }
    func testRelativeHours() { assert(NaturalDate.parse("2小时后", now: now, timeZone: tz), "2026-10-24", "11:00") }
    func testRelativeDaysNoTime() { assert(NaturalDate.parse("3天后", now: now, timeZone: tz), "2026-10-27", "00:00") }
    func testToday() { assert(NaturalDate.parse("今天下午2点", now: now, timeZone: tz), "2026-10-24", "14:00") }
    func testNoon() { assert(NaturalDate.parse("中午12点半", now: now, timeZone: tz), "2026-10-24", "12:30") }
    func testMorningDefault() { assert(NaturalDate.parse("后天早上", now: now, timeZone: tz), "2026-10-26", "08:00") }

    func testISOPassthrough() {
        assert(NaturalDate.parse("2026-10-25T02:00:00Z", now: now, timeZone: tz), "2026-10-25", "10:00")
    }

    func testExplicitFormat() {
        assert(NaturalDate.parse("2026-10-25 09:30", now: now, timeZone: tz), "2026-10-25", "09:30")
    }

    func testWeekday() {
        let d = NaturalDate.parse("周三", now: now, timeZone: tz)
        XCTAssertNotNil(d)
        XCTAssertEqual(cal.component(.weekday, from: d!), 4) // 周三
        XCTAssertGreaterThanOrEqual(d!, cal.startOfDay(for: now))
    }

    func testNextWeek() {
        let d = NaturalDate.parse("下周一", now: now, timeZone: tz)
        XCTAssertNotNil(d)
        XCTAssertEqual(cal.component(.weekday, from: d!), 2)
        // 必须至少 7 天后
        let delta = cal.dateComponents([.day], from: cal.startOfDay(for: now), to: cal.startOfDay(for: d!)).day!
        XCTAssertGreaterThanOrEqual(delta, 7)
    }

    func testGarbage() {
        XCTAssertNil(NaturalDate.parse("随便", now: now, timeZone: tz))
        XCTAssertNil(NaturalDate.parse("", now: now, timeZone: tz))
    }

    func testClockFormat() {
        assert(NaturalDate.parse("明天 19:05", now: now, timeZone: tz), "2026-10-25", "19:05")
    }
}
