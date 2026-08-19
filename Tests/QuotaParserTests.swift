import Foundation

enum QuotaParserTests {
    static func run() -> Int {
        var failed = 0
        let fixtures = URL(fileURLWithPath: CommandLine.arguments[0])
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures")
        // Prefer CWD-relative fixtures
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Fixtures")
        let dir = FileManager.default.fileExists(atPath: root.path) ? root : fixtures
        let now = QuotaParser.parseRFC3339("2026-08-15T00:00:00Z")!

        failed += check("weekly 2.0 -> 98") {
            let data = try Data(contentsOf: dir.appendingPathComponent("billing-weekly.json"))
            let snap = try QuotaParser.parse(data: data, now: now, fetchedAt: now).get()
            return snap.remainingPercent == 98 && snap.usedPercent == 2.0
        }
        failed += check("used 0/100/2.5") {
            let data = try Data(contentsOf: dir.appendingPathComponent("billing-used-bounds.json"))
            let obj = try JSONSerialization.jsonObject(with: data) as! [String: Any]
            func parse(_ key: String) throws -> Result<QuotaSnapshot, QuotaError> {
                let body = try JSONSerialization.data(withJSONObject: obj[key]!)
                return QuotaParser.parse(data: body, now: now, fetchedAt: now)
            }
            guard case .success(let z) = try parse("zero"), z.remainingPercent == 100 else { return false }
            guard case .success(let f) = try parse("full"), f.remainingPercent == 0 else { return false }
            guard case .success(let h) = try parse("half"), h.remainingPercent == 97 else { return false }
            guard case .failure(.parse) = try parse("neg") else { return false }
            guard case .failure(.parse) = try parse("over") else { return false }
            return true
        }
        failed += check("non-weekly") {
            let data = try Data(contentsOf: dir.appendingPathComponent("billing-non-weekly.json"))
            if case .failure(.parse) = QuotaParser.parse(data: data, now: now, fetchedAt: now) { return true }
            return false
        }
        failed += check("missing product") {
            let data = try Data(contentsOf: dir.appendingPathComponent("billing-missing-product.json"))
            if case .failure(.parse) = QuotaParser.parse(data: data, now: now, fetchedAt: now) { return true }
            return false
        }
        failed += check("duplicate product") {
            let data = try Data(contentsOf: dir.appendingPathComponent("billing-duplicate-product.json"))
            if case .failure(.parse) = QuotaParser.parse(data: data, now: now, fetchedAt: now) { return true }
            return false
        }
        failed += check("expired period") {
            let data = try Data(contentsOf: dir.appendingPathComponent("billing-expired-period.json"))
            if case .failure(.periodEnded) = QuotaParser.parse(data: data, now: now, fetchedAt: now) { return true }
            return false
        }
        failed += check("future period") {
            let json = """
            {"config":{"currentPeriod":{"type":"USAGE_PERIOD_TYPE_WEEKLY","start":"2026-09-01T00:00:00Z","end":"2026-09-08T00:00:00Z"},"productUsage":[{"product":"GrokBuild","usagePercent":1}]}}
            """
            if case .failure(.periodNotStarted) = QuotaParser.parse(data: Data(json.utf8), now: now, fetchedAt: now) {
                return true
            }
            return false
        }
        failed += check("inverted period") {
            let json = """
            {"config":{"currentPeriod":{"type":"USAGE_PERIOD_TYPE_WEEKLY","start":"2026-08-18T00:00:00Z","end":"2026-08-11T00:00:00Z"},"productUsage":[{"product":"GrokBuild","usagePercent":1}]}}
            """
            if case .failure(.parse) = QuotaParser.parse(data: Data(json.utf8), now: now, fetchedAt: now) {
                return true
            }
            return false
        }
        failed += check("remaining formula") {
            QuotaParser.remaining(usedPercent: 2.5) == 97
                && QuotaParser.remaining(usedPercent: 2.0) == 98
        }
        failed += check("staleAge uses max of wall and mono") {
            let snap = QuotaSnapshot(
                usedPercent: 2,
                remainingPercent: 98,
                periodType: "USAGE_PERIOD_TYPE_WEEKLY",
                periodStart: now,
                periodEnd: now.addingTimeInterval(3600),
                fetchedAt: now.addingTimeInterval(3600),
                fetchedMonoNanos: 1_000_000_000
            )
            let later = DispatchTime(uptimeNanoseconds: 1_000_000_000 + 7 * 3600 * 1_000_000_000)
            let age = snap.staleAge(wallNow: now, monoNow: later)
            return age > 6 * 3600
        }
        failed += check("bool usagePercent rejected") {
            let json = """
            {"config":{"currentPeriod":{"type":"USAGE_PERIOD_TYPE_WEEKLY","start":"2026-08-11T00:00:00Z","end":"2026-08-18T00:00:00Z"},"productUsage":[{"product":"GrokBuild","usagePercent":true}]}}
            """
            if case .failure(.parse) = QuotaParser.parse(data: Data(json.utf8), now: now, fetchedAt: now) {
                return true
            }
            return false
        }
        _ = dir
        return failed
    }

    private static func check(_ name: String, _ body: () throws -> Bool) -> Int {
        do {
            if try body() {
                print("ok  \(name)")
                return 0
            }
            print("FAIL \(name)")
            return 1
        } catch {
            print("FAIL \(name): \(error)")
            return 1
        }
    }
}
