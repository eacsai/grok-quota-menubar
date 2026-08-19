import Foundation

enum QuotaError: String, Error, Equatable {
    case notLoggedIn = "未登录"
    case grokBusy = "Grok占用中"
    case loginExpired = "登录已过期"
    case network = "网络失败"
    case parse = "解析失败"
    case periodNotStarted = "周期未开始"
    case periodEnded = "周期已结束"
    case persistFailed = "写入失败"
}

enum PeriodClass: Equatable {
    case active
    case notStarted
    case ended
    case malformed
}

struct QuotaSnapshot: Equatable {
    var usedPercent: Double
    var remainingPercent: Int
    var periodType: String
    var periodStart: Date
    var periodEnd: Date
    var fetchedAt: Date
    var fetchedMonoNanos: UInt64

    func staleAge(wallNow: Date, monoNow: DispatchTime) -> TimeInterval {
        let wall = wallNow.timeIntervalSince(fetchedAt)
        let mono = Double(monoNow.uptimeNanoseconds &- fetchedMonoNanos) / 1_000_000_000
        return max(wall, mono)
    }

    var compactReset: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        f.dateFormat = "M/d HH:mm"
        return f.string(from: periodEnd)
    }

    var fullReset: String {
        let f = DateFormatter()
        f.locale = Locale.current
        f.timeZone = TimeZone.current
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: periodEnd)
    }
}

enum QuotaParser {
    static let skew: TimeInterval = 120

    static func remaining(usedPercent: Double) -> Int {
        let rounded = Int(usedPercent.rounded(.toNearestOrAwayFromZero))
        return min(100, max(0, 100 - rounded))
    }

    static func parseRFC3339(_ raw: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = f.date(from: raw) { return date }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: raw)
    }

    static func formatRFC3339(_ date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.string(from: date)
    }

    static func classifyPeriod(start: Date, end: Date, now: Date) -> PeriodClass {
        if start >= end { return .malformed }
        if now < start.addingTimeInterval(-skew) { return .notStarted }
        if now >= end.addingTimeInterval(skew) { return .ended }
        return .active
    }

    static func parse(
        data: Data,
        now: Date,
        fetchedAt: Date,
        fetchedMonoNanos: UInt64 = DispatchTime.now().uptimeNanoseconds
    ) -> Result<QuotaSnapshot, QuotaError> {
        guard
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let config = root["config"] as? [String: Any],
            let period = config["currentPeriod"] as? [String: Any],
            let type = period["type"] as? String,
            let startRaw = period["start"] as? String,
            let endRaw = period["end"] as? String,
            let start = parseRFC3339(startRaw),
            let end = parseRFC3339(endRaw)
        else {
            return .failure(.parse)
        }
        guard type == "USAGE_PERIOD_TYPE_WEEKLY" else { return .failure(.parse) }
        guard let products = config["productUsage"] as? [[String: Any]] else {
            return .failure(.parse)
        }
        let grokRows = products.filter { ($0["product"] as? String) == "GrokBuild" }
        guard grokRows.count == 1 else { return .failure(.parse) }
        guard let used = numericPercent(grokRows[0]["usagePercent"]) else {
            return .failure(.parse)
        }

        switch classifyPeriod(start: start, end: end, now: now) {
        case .malformed:
            return .failure(.parse)
        case .notStarted:
            return .failure(.periodNotStarted)
        case .ended:
            return .failure(.periodEnded)
        case .active:
            break
        }

        return .success(
            QuotaSnapshot(
                usedPercent: used,
                remainingPercent: remaining(usedPercent: used),
                periodType: type,
                periodStart: start,
                periodEnd: end,
                fetchedAt: fetchedAt,
                fetchedMonoNanos: fetchedMonoNanos
            )
        )
    }

    private static func numericPercent(_ value: Any?) -> Double? {
        if isJSONBool(value) { return nil }
        let number: Double
        if let d = value as? Double {
            number = d
        } else if let i = value as? Int {
            number = Double(i)
        } else if let n = value as? NSNumber {
            number = n.doubleValue
        } else {
            return nil
        }
        guard number.isFinite, number >= 0, number <= 100 else { return nil }
        return number
    }

    static func isJSONBool(_ value: Any?) -> Bool {
        guard let value else { return false }
        if let num = value as? NSNumber {
            return CFGetTypeID(num) == CFBooleanGetTypeID()
        }
        return value is Bool
    }
}
