import Foundation

/// 中文自然语言日期时间解析（无第三方依赖）。
/// 支持：今天/明天/后天/大后天、N天后/小时后/分钟后、周X/星期X/下周X、上午/下午/晚上 + N点(半|M分)、裸 ISO8601 直通。
public enum NaturalDate {
    public static func parse(_ input: String, now: Date, timeZone: TimeZone) -> Date? {
        let s = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if s.isEmpty { return nil }

        // ISO8601 直通
        if let iso = ISO8601DateFormatter().date(from: input.trimmingCharacters(in: .whitespaces)) {
            return iso
        }
        let df = DateFormatter()
        df.timeZone = timeZone
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "yyyy-MM-dd HH:mm"
        if let d = df.date(from: input.trimmingCharacters(in: .whitespaces)) { return d }

        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone

        var dayOffset = 0
        var timeSet = false
        var hour = 9, minute = 0

        // —— 天数偏移 ——
        if let r = s.range(of: #"(\d+)\s*(天|日)后"#, options: .regularExpression), let n = Int(s[r].filter { $0.isNumber }) {
            dayOffset = n
        } else if s.contains("大后天") { dayOffset = 3 }
        else if s.contains("后天") { dayOffset = 2 }
        else if s.contains("明天") || s.contains("明日") { dayOffset = 1 }
        else if s.contains("今天") || s.contains("今晚") || s.contains("今日") { dayOffset = 0 }

        // 周X（下周优先）
        let weekdays = ["周日":1, "周天":1, "周一":2, "周二":3, "周三":4, "周四":5, "周五":6, "周六":7,
                        "星期日":1, "星期天":1, "星期一":2, "星期二":3, "星期三":4, "星期四":5, "星期五":6, "星期六":7]
        var weekdayTarget: Int?
        for (k, v) in weekdays where s.contains(k) { weekdayTarget = v; break }
        if let wt = weekdayTarget {
            let nowWeekday = cal.component(.weekday, from: now)
            var delta = wt - nowWeekday
            if delta < 0 { delta += 7 }
            if s.contains("下周") || s.contains("下星期") {
                delta = delta <= 0 ? delta : delta + 7
            }
            dayOffset = max(dayOffset, delta)
        }

        // —— 时刻 ——
        // "30分钟后" / "2小时后"
        if let r = s.range(of: #"(\d+)\s*分钟后"#, options: .regularExpression), let n = Int(s[r].filter { $0.isNumber }) {
            return cal.date(byAdding: .minute, value: n, to: now)
        }
        if let r = s.range(of: #"(\d+)\s*小时后"#, options: .regularExpression), let n = Int(s[r].filter { $0.isNumber }) {
            return cal.date(byAdding: .hour, value: n, to: now)
        }

        // 上午/下午/晚上修正 + N点(半|M分)
        let isPM = s.contains("下午") || s.contains("傍晚") || s.contains("晚上") || s.contains("今晚")
        let isNoon = s.contains("中午")
        let isMorning = isNoon ? true : (s.contains("上午") || s.contains("早上") || s.contains("早晨") || s.contains("凌晨"))
        if let r = s.range(of: #"(\d{1,2})\s*(点|时)"#, options: .regularExpression) {
            let nums = s[r].filter { $0.isNumber }
            if let h = Int(nums) {
                timeSet = true
                hour = h
                if isPM && h < 12 { hour = h + 12 }
                if isNoon && h < 12 { hour = h + 12 }
                // 点半 / 点30分
                if s.contains("点半") || s.contains("点30") || s.contains("时30") { minute = 30 }
                if let mr = s.range(of: #"(点|时)\s*(\d{1,2})\s*分"#, options: .regularExpression) {
                    let seg = String(s[mr])
                    if let m = Int(seg.filter { $0.isNumber }), seg.count >= 2 {
                        // 去掉小时位：取最后两位以内的分钟
                        let digits = seg.filter { $0.isNumber }
                        if digits.count >= 3, let mm = Int(String(digits.suffix(2))) { minute = mm }
                    }
                }
            }
        } else if let r = s.range(of: #"(\d{1,2}):(\d{2})"#, options: .regularExpression) {
            let seg = String(s[r])
            let parts = seg.split(separator: ":").compactMap { Int($0) }
            if parts.count == 2 {
                timeSet = true
                hour = parts[0]
                minute = parts[1]
                if isPM && hour < 12 { hour += 12 }
            }
        } else if s.contains("中午") { hour = 12; timeSet = true }
        else if s.contains("早上") || s.contains("早晨") { hour = 8; timeSet = true }
        else if s.contains("下午") { hour = 14; timeSet = true }
        else if s.contains("晚上") || s.contains("今晚") { hour = 20; timeSet = true }

        guard timeSet || dayOffset > 0 || weekdayTarget != nil else { return nil }

        let base = cal.startOfDay(for: now)
        guard let day = cal.date(byAdding: .day, value: dayOffset, to: base) else { return nil }
        if timeSet || weekdayTarget != nil {
            if hour < 12 && isMorning { hour = hour } // 上午保持
            guard let at = cal.date(bySettingHour: hour, minute: minute, second: 0, of: day) else { return nil }
            return at
        }
        return day
    }
}
