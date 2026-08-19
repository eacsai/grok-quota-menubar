import Foundation

enum AuthPolicyTests {
    static func run() -> Int {
        var failed = 0
        failed += check("form encode reserved") {
            AuthStore.formEncode("a+b=c&d e") == "a%2Bb%3Dc%26d+e"
        }
        failed += check("form encode rejects non-ascii as raw") {
            guard let encoded = AuthStore.formEncode("tokén") else { return false }
            return encoded.contains("%") && !encoded.contains("é")
        }
        failed += check("empty tokens -> 未登录") {
            let json = """
            {"https://auth.x.ai::aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee":{"oidc_issuer":"https://auth.x.ai","oidc_client_id":"aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee","key":"","refresh_token":"r"}}
            """
            if case .failure(.notLoggedIn) = AuthStore.selectEntry(from: Data(json.utf8)) { return true }
            return false
        }
        failed += check("select unique entry") {
            let id = "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
            let json = """
            {"https://auth.x.ai::\(id)":{"oidc_issuer":"https://auth.x.ai","oidc_client_id":"\(id)","key":"tok-old","refresh_token":"ref-old","expires_at":"2026-08-18T21:53:23.684338Z"}}
            """
            guard case .success(let s) = AuthStore.selectEntry(from: Data(json.utf8)) else { return false }
            let exp = QuotaParser.parseRFC3339("2026-08-18T21:53:23.684338Z")
            return s.accessToken == "tok-old" && s.refreshToken == "ref-old" && s.expiresAt == exp && exp != nil
        }
        failed += check("bad expires_in rejected") {
            let body = #"{"access_token":"x","expires_in":0}"#.data(using: .utf8)!
            if case .failure(.network) = AuthStore.parseRefreshResponse(body, httpStatus: 200) { return true }
            return false
        }
        failed += check("bool expires_in rejected") {
            let body = #"{"access_token":"x","expires_in":true}"#.data(using: .utf8)!
            if case .failure(.network) = AuthStore.parseRefreshResponse(body, httpStatus: 200) { return true }
            return false
        }
        failed += check("good refresh parse") {
            let body = #"{"access_token":"new","expires_in":21600}"#.data(using: .utf8)!
            guard case .success(let p) = AuthStore.parseRefreshResponse(body, httpStatus: 200) else { return false }
            return p.access == "new" && p.refresh == nil && p.expiresIn == 21600
        }
        failed += check("CAS / persist / 0600") {
            let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("grok-quota-test-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: tmp.appendingPathComponent(".grok"), withIntermediateDirectories: true)
            let id = "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
            let key = "https://auth.x.ai::\(id)"
            let auth: [String: Any] = [
                key: [
                    "oidc_issuer": "https://auth.x.ai",
                    "oidc_client_id": id,
                    "key": "tok-old",
                    "refresh_token": "ref-old",
                    "expires_at": "2026-08-18T21:53:23.684338Z",
                    "email": "keep-me",
                ]
            ]
            let authURL = tmp.appendingPathComponent(".grok/auth.json")
            try JSONSerialization.data(withJSONObject: auth).write(to: authURL)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: authURL.path)
            guard case .success(let snap) = AuthStore.readSnapshot(home: tmp) else { return false }

            var wrong = snap
            wrong.accessToken = "someone-else"
            let casMiss = AuthStore.writeIfCAS(
                home: tmp, expected: wrong, newAccess: "tok-new", newRefresh: nil,
                expiresIn: 3600, now: Date()
            )
            if casMiss != .casMismatch { return false }
            guard case .success(let still) = AuthStore.readSnapshot(home: tmp), still.accessToken == "tok-old" else {
                return false
            }

            let ok = AuthStore.writeIfCAS(
                home: tmp, expected: snap, newAccess: "tok-new", newRefresh: "ref-new",
                expiresIn: 3600, now: Date()
            )
            guard ok == .wrote, case .success(let next) = AuthStore.readSnapshot(home: tmp) else { return false }
            let perms = try FileManager.default.attributesOfItem(atPath: authURL.path)[.posixPermissions] as? NSNumber
            let mode = perms?.uint16Value ?? 0
            try? FileManager.default.removeItem(at: tmp)
            return next.accessToken == "tok-new" && next.refreshToken == "ref-new" && (mode & 0o777) == 0o600
        }
        failed += check("writeFailed is not casMismatch") {
            let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("grok-quota-ro-\(UUID().uuidString)", isDirectory: true)
            let grok = tmp.appendingPathComponent(".grok")
            try FileManager.default.createDirectory(at: grok, withIntermediateDirectories: true)
            let id = "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
            let key = "https://auth.x.ai::\(id)"
            let auth: [String: Any] = [
                key: [
                    "oidc_issuer": "https://auth.x.ai",
                    "oidc_client_id": id,
                    "key": "tok-old",
                    "refresh_token": "ref-old",
                ]
            ]
            let authURL = grok.appendingPathComponent("auth.json")
            try JSONSerialization.data(withJSONObject: auth).write(to: authURL)
            guard case .success(let snap) = AuthStore.readSnapshot(home: tmp) else { return false }
            try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: grok.path)
            let result = AuthStore.commitIfUnchanged(
                home: tmp, expected: snap, newAccess: "tok-new", newRefresh: "ref-new",
                expiresIn: 3600, now: Date()
            )
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: grok.path)
            try? FileManager.default.removeItem(at: tmp)
            return result == .writeFailed
        }
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
