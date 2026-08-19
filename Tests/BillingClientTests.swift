import Foundation

enum BillingClientTests {
    static func run() -> Int {
        var failed = 0
        failed += check("400 invalid_grant is loginExpired") {
            let body = #"{"error":"invalid_grant"}"#.data(using: .utf8)!
            return BillingClient.isRefreshLoginExpired(status: 400, body: body)
        }
        failed += check("403 is loginExpired") {
            BillingClient.isRefreshLoginExpired(status: 403, body: Data())
        }
        failed += check("500 is not loginExpired") {
            !BillingClient.isRefreshLoginExpired(status: 500, body: Data())
        }
        failed += check("fetch maps 400 refresh to 登录已过期") {
            let tmp = try makeAuthHome()
            defer { try? FileManager.default.removeItem(at: tmp) }
            let outcome = BillingClient.fetch(
                home: tmp,
                now: Date(),
                grokRunning: { false },
                perform: { _, kind, _ in
                    if kind == .refreshPOST {
                        return HTTPResult(
                            status: 400,
                            body: #"{"error":"invalid_grant"}"#.data(using: .utf8)!,
                            connectionFailed: false
                        )
                    }
                    return HTTPResult(status: 500, body: Data(), connectionFailed: false)
                },
                discoverProxy: { nil }
            )
            return outcome.snapshot == nil && outcome.error == .loginExpired
        }
        failed += check("401 while grok running still refreshes under sibling lock") {
            let tmp = try makeAuthHome(expiresFar: true)
            defer { try? FileManager.default.removeItem(at: tmp) }
            var posted = false
            let outcome = BillingClient.fetch(
                home: tmp,
                now: Date(),
                grokRunning: { true },
                perform: { _, kind, _ in
                    if kind == .refreshPOST {
                        posted = true
                        return HTTPResult(
                            status: 400,
                            body: #"{"error":"invalid_grant"}"#.data(using: .utf8)!,
                            connectionFailed: false
                        )
                    }
                    return HTTPResult(status: 401, body: Data(), connectionFailed: false)
                },
                discoverProxy: { nil }
            )
            return posted && outcome.error == .loginExpired
        }
        failed += check("lock timeout is grokBusy") {
            let tmp = try makeAuthHome()
            defer { try? FileManager.default.removeItem(at: tmp) }
            let child = try AuthLockTests.holdLockInChild(tmp, seconds: 3)
            defer { child.terminate() }
            guard AuthLockTests.waitUntilChildHoldsLock(home: tmp) else { return false }
            let outcome = BillingClient.fetch(
                home: tmp,
                now: Date(),
                grokRunning: { true },
                perform: { _, _, _ in
                    HTTPResult(status: 500, body: Data(), connectionFailed: false)
                },
                discoverProxy: { nil },
                lockTimeout: 0.3
            )
            return outcome.error == .grokBusy
        }
        failed += check("refresh writeFailed maps to persistFailed") {
            let tmp = try makeAuthHome()
            let grok = tmp.appendingPathComponent(".grok")
            defer {
                try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: grok.path)
                try? FileManager.default.removeItem(at: tmp)
            }
            // Pre-create the lock file so open() can succeed when the
            // directory is later made 0555 (otherwise acquire spins 25s
            // and returns grokBusy).
            FileManager.default.createFile(atPath: grok.appendingPathComponent("auth.json.lock").path, contents: Data())
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o555],
                ofItemAtPath: grok.path
            )
            let outcome = BillingClient.fetch(
                home: tmp,
                now: Date(),
                grokRunning: { false },
                perform: { _, kind, _ in
                    if kind == .refreshPOST {
                        return HTTPResult(
                            status: 200,
                            body: #"{"access_token":"n","refresh_token":"r2","expires_in":3600}"#.data(using: .utf8)!,
                            connectionFailed: false
                        )
                    }
                    return HTTPResult(status: 200, body: Data(), connectionFailed: false)
                },
                discoverProxy: { nil }
            )
            return outcome.error == .persistFailed
        }
        failed += check("401 with grok idle is not grokBusy") {
            let tmp = try makeAuthHome(expiresFar: true)
            defer { try? FileManager.default.removeItem(at: tmp) }
            let outcome = BillingClient.fetch(
                home: tmp,
                now: Date(),
                grokRunning: { false },
                perform: { _, kind, _ in
                    if kind == .refreshPOST {
                        return HTTPResult(
                            status: 400,
                            body: #"{"error":"invalid_grant"}"#.data(using: .utf8)!,
                            connectionFailed: false
                        )
                    }
                    return HTTPResult(status: 401, body: Data(), connectionFailed: false)
                },
                discoverProxy: { nil }
            )
            return outcome.error == .loginExpired
        }
        return failed
    }

    private static func makeAuthHome(expiresFar: Bool = false) throws -> URL {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(
            "grok-quota-bill-\(UUID().uuidString)", isDirectory: true
        )
        try FileManager.default.createDirectory(at: tmp.appendingPathComponent(".grok"), withIntermediateDirectories: true)
        let id = "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
        let key = "https://auth.x.ai::\(id)"
        let exp = expiresFar
            ? QuotaParser.formatRFC3339(Date().addingTimeInterval(3600))
            : "2020-01-01T00:00:00.000000Z"
        let auth: [String: Any] = [
            key: [
                "oidc_issuer": "https://auth.x.ai",
                "oidc_client_id": id,
                "key": "tok-old",
                "refresh_token": "ref-old",
                "expires_at": exp,
            ]
        ]
        try JSONSerialization.data(withJSONObject: auth)
            .write(to: tmp.appendingPathComponent(".grok/auth.json"))
        return tmp
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
