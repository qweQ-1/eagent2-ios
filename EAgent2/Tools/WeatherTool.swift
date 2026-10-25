import CoreLocation
import Foundation

/// 定位 + Open-Meteo 天气（免 key）。
public enum WeatherTool {

    public static func forecastURL(lat: Double, lon: Double) -> URL? {
        var c = URLComponents(string: "https://api.open-meteo.com/v1/forecast")
        c?.queryItems = [
            URLQueryItem(name: "latitude", value: String(lat)),
            URLQueryItem(name: "longitude", value: String(lon)),
            URLQueryItem(name: "current", value: "temperature_2m,relative_humidity_2m,apparent_temperature,weather_code,wind_speed_10m"),
            URLQueryItem(name: "daily", value: "temperature_2m_max,temperature_2m_min,precipitation_probability_max"),
            URLQueryItem(name: "timezone", value: "auto")
        ]
        return c?.url
    }

    static func codeText(_ code: Int) -> String {
        let map: [Int: String] = [
            0: "晴", 1: "大致晴", 2: "局部多云", 3: "阴",
            45: "雾", 48: "雾凇", 51: "毛毛雨", 53: "毛毛雨", 55: "毛毛雨",
            61: "小雨", 63: "中雨", 65: "大雨", 66: "冻雨", 67: "冻雨",
            71: "小雪", 73: "中雪", 75: "大雪", 77: "雪粒",
            80: "阵雨", 81: "阵雨", 82: "强阵雨", 85: "阵雪", 86: "强阵雪",
            95: "雷暴", 96: "雷暴伴冰雹", 99: "雷暴伴冰雹"
        ]
        return map[code] ?? "天气代码 \(code)"
    }

    @MainActor
    public static func run(lat: Double, lon: Double) async -> String {
        guard let url = forecastURL(lat: lat, lon: lon) else { return FilesTool.err("构造天气请求失败") }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
            let cur = obj["current"] as? [String: Any] ?? [:]
            let daily = obj["daily"] as? [String: Any] ?? [:]
            let maxArr = daily["temperature_2m_max"] as? [Any] ?? []
            let minArr = daily["temperature_2m_min"] as? [Any] ?? []
            let popArr = daily["precipitation_probability_max"] as? [Any] ?? []
            let code = (cur["weather_code"] as? NSNumber)?.intValue ?? -999
            var out: [String: String] = [:]
            out["weather"] = codeText(code)
            out["temperature_c"] = num(cur["temperature_2m"])
            out["feels_like_c"] = num(cur["apparent_temperature"])
            out["humidity_pct"] = num(cur["relative_humidity_2m"])
            out["wind_kmh"] = num(cur["wind_speed_10m"])
            out["today_max_c"] = num(maxArr.first)
            out["today_min_c"] = num(minArr.first)
            out["rain_probability_pct"] = num(popArr.first)
            out["timezone"] = obj["timezone"] as? String ?? "auto"
            return FilesTool.ok(out)
        } catch {
            return FilesTool.err("天气请求失败：" + error.localizedDescription)
        }
    }

    static func num(_ v: Any?) -> String {
        if let n = v as? NSNumber { return n.stringValue }
        if let d = v as? Double { return String(format: "%.1f", d) }
        return "n/a"
    }
}

/// 一次性定位（超时 15 秒）
@MainActor
public final class LocationProvider: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var cont: CheckedContinuationHolder?
    public private(set) var last: CLLocation?

    public override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    public func current(timeout: TimeInterval = 15) async -> String {
        let status = manager.authorizationStatus
        guard status == .authorizedWhenInUse || status == .authorizedAlways else {
            if status == .notDetermined {
                manager.requestWhenInUseAuthorization()
            }
            if manager.authorizationStatus != .authorizedWhenInUse, manager.authorizationStatus != .authorizedAlways {
                return FilesTool.err("未获得定位权限，请在 设置 → EAgent 中允许「使用期间定位」")
            }
        }
        if let last = last {
            return ok(last)
        }
        return await withCheckedContinuation { c in
            cont = CheckedContinuationHolder(c)
            manager.requestLocation()
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                if let cont = cont, !cont.done { cont.done = true; c.resume(returning: FilesTool.err("定位超时")) }
            }
        }
    }

    private func ok(_ loc: CLLocation) -> String {
        FilesTool.ok(["lat": String(loc.coordinate.latitude), "lon": String(loc.coordinate.longitude),
                      "accuracy_m": String(format: "%.0f", loc.horizontalAccuracy)])
    }

    // CLLocationManagerDelegate 的回调是 nonisolated 要求，必须显式标注并切回主线程
    public nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.last = loc
            if let cont = self.cont, !cont.done {
                cont.done = true
                self.cont = nil
                cont.cont.resume(returning: self.ok(loc))
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        let msg = "定位失败：" + error.localizedDescription
        Task { @MainActor [weak self] in
            guard let self else { return }
            if let cont = self.cont, !cont.done {
                cont.done = true
                self.cont = nil
                cont.cont.resume(returning: FilesTool.err(msg))
            }
        }
    }
}

final class CheckedContinuationHolder: @unchecked Sendable {
    let cont: CheckedContinuation<String, Never>
    var done = false
    init(_ c: CheckedContinuation<String, Never>) { cont = c }
}
