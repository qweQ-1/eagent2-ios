import EventKit
import Foundation

/// 提醒事项 / 日历（EventKit，iOS 17 起用全量授权 API）
public enum EventKitTools {

    // MARK: - 提醒事项

    @MainActor
    public static func createReminder(title: String, notes: String, due: String, timeZone: TimeZone) async -> String {
        let store = EKEventStore()
        let granted = await authorize(store: store, type: .reminder)
        guard granted else { return FilesTool.err("未获得「提醒事项」权限，请在 设置 → EAgent 中允许") }
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return FilesTool.err("提醒标题不能为空") }

        let reminder = EKReminder(eventStore: store)
        reminder.title = t
        reminder.notes = notes.isEmpty ? nil : notes
        if !due.trimmingCharacters(in: .whitespaces).isEmpty {
            guard let date = NaturalDate.parse(due, now: Date(), timeZone: timeZone) else {
                return FilesTool.err("无法理解到期时间：" + due)
            }
            var cal = Calendar(identifier: .gregorian)
            cal.timeZone = timeZone
            reminder.dueDateComponents = cal.dateComponents([.year, .month, .day, .hour, .minute], from: date)
            reminder.addAlarm(EKAlarm(absoluteDate: date))
        }
        do {
            try store.save(reminder, commit: true)
            return FilesTool.ok(["title": t, "due": due, "notes": notes])
        } catch {
            return FilesTool.err("保存提醒失败：" + error.localizedDescription)
        }
    }

    // MARK: - 日历日程

    @MainActor
    public static func createEvent(title: String, start: String, durationMin: Int, notes: String, timeZone: TimeZone) async -> String {
        let store = EKEventStore()
        let granted = await authorize(store: store, type: .event)
        guard granted else { return FilesTool.err("未获得「日历」权限，请在 设置 → EAgent 中允许") }
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return FilesTool.err("日程标题不能为空") }
        guard let s = NaturalDate.parse(start, now: Date(), timeZone: timeZone) else {
            return FilesTool.err("无法理解开始时间：" + start)
        }
        let event = EKEvent(eventStore: store)
        event.title = t
        event.startDate = s
        let dur = durationMin > 0 ? durationMin : 60
        event.endDate = s.addingTimeInterval(TimeInterval(dur * 60))
        event.notes = notes.isEmpty ? nil : notes
        event.calendar = store.defaultCalendarForNewEvents
        do {
            try store.save(event, span: .thisEvent, commit: true)
            return FilesTool.ok(["title": t, "start": iso(s, timeZone), "minutes": String(dur)])
        } catch {
            return FilesTool.err("保存日程失败：" + error.localizedDescription)
        }
    }

    // MARK: - 授权（iOS 17+ 全量授权 API）

    @MainActor
    static func authorize(store: EKEventStore, type: EKEntityType) async -> Bool {
        if #available(iOS 17.0, *) {
            switch type {
            case .event: return await request { store.requestFullAccessToEvents() }
            case .reminder: return await request { store.requestFullAccessToReminders() }
            default: break
            }
        }
        return await withCheckedContinuation { c in
            store.requestAccess(to: type) { ok, _ in
                Task { @MainActor in c.resume(returning: ok) }
            }
        }
    }

    @available(iOS 17.0, *)
    static func request(_ body: @escaping () async throws -> Bool) async -> Bool {
        return (try? await body()) ?? false
    }

    static func iso(_ d: Date, _ tz: TimeZone) -> String {
        let f = ISO8601DateFormatter()
        f.timeZone = tz
        return f.string(from: d)
    }
}
