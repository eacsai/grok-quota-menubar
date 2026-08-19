import Darwin
import Foundation

struct AuthSnapshot: Equatable {
    var entryKey: String
    var clientID: String
    var accessToken: String
    var refreshToken: String
    var expiresAt: Date?
}

enum PersistResult: Equatable {
    case wrote
    case casMismatch
    case writeFailed
}

enum AuthStore {
    static let nearExpiry: TimeInterval = 5 * 60
    static let minExpiresIn: Double = 60
    static let maxExpiresIn: Double = 172_800

    static func formEncode(_ value: String) -> String? {
        var allowed = CharacterSet()
        allowed.insert(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._*")
        guard let escaped = value.addingPercentEncoding(withAllowedCharacters: allowed) else {
            return nil
        }
        return escaped.replacingOccurrences(of: "%20", with: "+")
    }

    static func authURL(home: URL) -> URL {
        home.appendingPathComponent(".grok/auth.json")
    }

    static func lockURL(home: URL) -> URL {
        AuthLock.lockURL(home: home)
    }

    static func needsRefresh(_ snapshot: AuthSnapshot, now: Date) -> Bool {
        guard let exp = snapshot.expiresAt else { return true }
        return exp.timeIntervalSince(now) <= nearExpiry
    }

    static func readSnapshot(home: URL) -> Result<AuthSnapshot, QuotaError> {
        let url = authURL(home: home)
        // Shared flock is best-effort. Same-process exclusive lock on
        // another fd makes LOCK_SH fail; ignore and still read.
        let lock = openLock(home: home, create: false)
        if let lock {
            _ = flock(lock, LOCK_SH | LOCK_NB)
        }
        defer {
            if let lock {
                flock(lock, LOCK_UN)
                close(lock)
            }
        }
        guard let data = try? Data(contentsOf: url) else { return .failure(.notLoggedIn) }
        return selectEntry(from: data)
    }

    static func selectEntry(from data: Data) -> Result<AuthSnapshot, QuotaError> {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .failure(.notLoggedIn)
        }
        var matches: [AuthSnapshot] = []
        let prefix = "https://auth.x.ai::"
        for (key, value) in root {
            guard key.hasPrefix(prefix) else { continue }
            let suffix = String(key.dropFirst(prefix.count))
            guard isUUID(suffix), let entry = value as? [String: Any] else { continue }
            guard (entry["oidc_issuer"] as? String) == "https://auth.x.ai" else { continue }
            guard let client = entry["oidc_client_id"] as? String, client == suffix else { continue }
            guard let access = nonempty(entry["key"]), let refresh = nonempty(entry["refresh_token"]) else {
                continue
            }
            var expires: Date?
            if let raw = entry["expires_at"] as? String {
                expires = QuotaParser.parseRFC3339(raw)
            }
            matches.append(
                AuthSnapshot(
                    entryKey: key,
                    clientID: client,
                    accessToken: access,
                    refreshToken: refresh,
                    expiresAt: expires
                )
            )
        }
        guard matches.count == 1 else { return .failure(.notLoggedIn) }
        return .success(matches[0])
    }

    static func parseRefreshResponse(_ data: Data, httpStatus: Int) -> Result<(access: String, refresh: String?, expiresIn: Double), QuotaError> {
        guard (200..<300).contains(httpStatus) else { return .failure(.network) }
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .failure(.network)
        }
        guard let access = nonempty(obj["access_token"]) else { return .failure(.network) }
        if QuotaParser.isJSONBool(obj["expires_in"]) { return .failure(.network) }
        let expiresIn: Double
        if let d = obj["expires_in"] as? Double {
            expiresIn = d
        } else if let i = obj["expires_in"] as? Int {
            expiresIn = Double(i)
        } else if let n = obj["expires_in"] as? NSNumber {
            expiresIn = n.doubleValue
        } else {
            return .failure(.network)
        }
        guard expiresIn.isFinite, expiresIn >= minExpiresIn, expiresIn <= maxExpiresIn else {
            return .failure(.network)
        }
        if let refresh = obj["refresh_token"] {
            guard let token = nonempty(refresh) else { return .failure(.network) }
            return .success((access, token, expiresIn))
        }
        return .success((access, nil, expiresIn))
    }

    @discardableResult
    static func writeIfCAS(
        home: URL,
        expected: AuthSnapshot,
        newAccess: String,
        newRefresh: String?,
        expiresIn: Double,
        now: Date
    ) -> PersistResult {
        // Caller should hold the sibling exclusive lock for refresh.
        // Persist is still CAS so a writer that ignored the lock cannot
        // be silently overwritten.
        return commitWithRetry(
            home: home, expected: expected, newAccess: newAccess,
            newRefresh: newRefresh, expiresIn: expiresIn, now: now
        )
    }

    private static func commitWithRetry(
        home: URL,
        expected: AuthSnapshot,
        newAccess: String,
        newRefresh: String?,
        expiresIn: Double,
        now: Date
    ) -> PersistResult {
        var last = commitIfUnchanged(
            home: home, expected: expected, newAccess: newAccess,
            newRefresh: newRefresh, expiresIn: expiresIn, now: now
        )
        if last != .writeFailed { return last }
        for _ in 0..<4 {
            usleep(20_000)
            last = commitIfUnchanged(
                home: home, expected: expected, newAccess: newAccess,
                newRefresh: newRefresh, expiresIn: expiresIn, now: now
            )
            if last != .writeFailed { return last }
        }
        return last
    }

    static func commitIfUnchanged(
        home: URL,
        expected: AuthSnapshot,
        newAccess: String,
        newRefresh: String?,
        expiresIn: Double,
        now: Date
    ) -> PersistResult {
        let url = authURL(home: home)
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            return .writeFailed
        }
        guard let rootObj = try? JSONSerialization.jsonObject(with: data),
              var root = rootObj as? [String: Any]
        else {
            return .writeFailed
        }
        guard var entry = root[expected.entryKey] as? [String: Any] else {
            return .casMismatch
        }
        guard (entry["oidc_client_id"] as? String) == expected.clientID,
              nonempty(entry["key"]) == expected.accessToken,
              nonempty(entry["refresh_token"]) == expected.refreshToken
        else {
            return .casMismatch
        }
        entry["key"] = newAccess
        if let newRefresh, !newRefresh.isEmpty {
            entry["refresh_token"] = newRefresh
        }
        entry["expires_at"] = QuotaParser.formatRFC3339(now.addingTimeInterval(expiresIn))
        root[expected.entryKey] = entry
        guard let out = try? JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys]) else {
            return .writeFailed
        }
        return atomicReplace(url: url, contents: out) ? .wrote : .writeFailed
    }

    static func atomicReplace(url: URL, contents: Data) -> Bool {
        let dir = url.deletingLastPathComponent()
        let temp = dir.appendingPathComponent("auth.json.\(UUID().uuidString).tmp")
        let tempPath = temp.path
        let fd = open(tempPath, O_CREAT | O_EXCL | O_WRONLY, 0o600)
        guard fd >= 0 else { return false }
        var ok = false
        defer {
            close(fd)
            if !ok { unlink(tempPath) }
        }
        let written: Int = contents.withUnsafeBytes { raw in
            guard let base = raw.bindMemory(to: UInt8.self).baseAddress else { return -1 }
            return write(fd, base, contents.count)
        }
        guard written == contents.count else { return false }
        guard fsync(fd) == 0 else { return false }
        guard rename(tempPath, url.path) == 0 else { return false }
        ok = true
        if let dirFD = opendir(dir.path) {
            fsync(dirfd(dirFD))
            closedir(dirFD)
        }
        _ = chmod(url.path, 0o600)
        return true
    }

    private static func openLock(home: URL, create: Bool) -> Int32? {
        let path = lockURL(home: home).path
        let flags = create ? (O_RDWR | O_CREAT | O_CLOEXEC) : (O_RDWR | O_CLOEXEC)
        let fd = open(path, flags, 0o600)
        guard fd >= 0 else { return nil }
        return fd
    }

    private static func nonempty(_ value: Any?) -> String? {
        guard let s = value as? String, !s.isEmpty else { return nil }
        return s
    }

    private static func isUUID(_ raw: String) -> Bool {
        raw.range(
            of: "^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$",
            options: .regularExpression
        ) != nil
    }
}
