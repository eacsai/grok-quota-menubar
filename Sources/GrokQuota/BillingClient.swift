import Foundation

struct FetchOutcome {
    var snapshot: QuotaSnapshot?
    var error: QuotaError?
    var grokWasRunning: Bool
}

enum BillingClient {
    static let oauthAuthErrors: Set<String> = [
        "invalid_grant", "invalid_client", "unauthorized_client",
    ]

    static func fetch(
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        now: Date = Date(),
        grokRunning: () -> Bool = { GrokProcess.officialGrokRunning() },
        perform: (URLRequest, HTTPKind, Int?) -> HTTPResult = HTTPClient.perform,
        discoverProxy: () -> Int? = { ClashProxy.discoverMixedPort() },
        lockTimeout: TimeInterval = AuthLock.acquireTimeout
    ) -> FetchOutcome {
        let runningAtStart = grokRunning()
        switch AuthStore.readSnapshot(home: home) {
        case .failure(let err):
            return FetchOutcome(snapshot: nil, error: err, grokWasRunning: runningAtStart)
        case .success(var creds):
            var refreshUsed = false

            if AuthStore.needsRefresh(creds, now: now) {
                switch refreshOnce(
                    home: home, creds: creds, now: now, force: false,
                    grokRunning: grokRunning, perform: perform, lockTimeout: lockTimeout
                ) {
                case .failure(let err):
                    return FetchOutcome(snapshot: nil, error: err, grokWasRunning: runningAtStart)
                case .success(let next):
                    creds = next.snapshot
                    if next.posted { refreshUsed = true }
                }
            }

            let first = billingGET(
                token: creds.accessToken, allowProxy: true, perform: perform, discoverProxy: discoverProxy
            )
            if first.connectionFailed {
                return FetchOutcome(snapshot: nil, error: .network, grokWasRunning: runningAtStart)
            }
            if first.status == 401 {
                if refreshUsed {
                    return FetchOutcome(snapshot: nil, error: .loginExpired, grokWasRunning: runningAtStart)
                }
                switch refreshOnce(
                    home: home, creds: creds, now: now, force: true,
                    grokRunning: grokRunning, perform: perform, lockTimeout: lockTimeout
                ) {
                case .failure(let err):
                    return FetchOutcome(snapshot: nil, error: err, grokWasRunning: runningAtStart)
                case .success(let next):
                    creds = next.snapshot
                    if next.posted { refreshUsed = true }
                }
                let second = billingGET(
                    token: creds.accessToken, allowProxy: true, perform: perform, discoverProxy: discoverProxy
                )
                return finish(http: second, now: now, grokWasRunning: runningAtStart, refreshUsed: refreshUsed)
            }
            return finish(http: first, now: now, grokWasRunning: runningAtStart, refreshUsed: refreshUsed)
        }
    }

    static func adoptedSibling(started: AuthSnapshot, disk: AuthSnapshot) -> AuthSnapshot? {
        if disk.refreshToken != started.refreshToken { return disk }
        if disk.accessToken != started.accessToken { return disk }
        return nil
    }

    static func isRefreshLoginExpired(status: Int, body: Data) -> Bool {
        if status == 400 || status == 403 { return true }
        guard let obj = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              let err = obj["error"] as? String
        else {
            return false
        }
        return oauthAuthErrors.contains(err)
    }

    private static func finish(http: HTTPResult, now: Date, grokWasRunning: Bool, refreshUsed: Bool) -> FetchOutcome {
        if http.connectionFailed {
            return FetchOutcome(snapshot: nil, error: .network, grokWasRunning: grokWasRunning)
        }
        if http.status == 401 {
            let err: QuotaError = refreshUsed ? .loginExpired : (grokWasRunning ? .grokBusy : .loginExpired)
            return FetchOutcome(snapshot: nil, error: err, grokWasRunning: grokWasRunning)
        }
        if !(200..<300).contains(http.status) || http.body.isEmpty {
            return FetchOutcome(snapshot: nil, error: .network, grokWasRunning: grokWasRunning)
        }
        switch QuotaParser.parse(data: http.body, now: now, fetchedAt: now) {
        case .success(let snap):
            return FetchOutcome(snapshot: snap, error: nil, grokWasRunning: grokWasRunning)
        case .failure(let err):
            return FetchOutcome(snapshot: nil, error: err, grokWasRunning: grokWasRunning)
        }
    }

    private static func billingGET(
        token: String,
        allowProxy: Bool,
        perform: (URLRequest, HTTPKind, Int?) -> HTTPResult,
        discoverProxy: () -> Int?
    ) -> HTTPResult {
        let req = HTTPClient.billingRequest(accessToken: token)
        let first = perform(req, .billingGET, nil)
        if first.connectionFailed, allowProxy, let port = discoverProxy() {
            return perform(req, .billingGET, port)
        }
        return first
    }

    private static func refreshOnce(
        home: URL,
        creds: AuthSnapshot,
        now: Date,
        force: Bool,
        grokRunning: () -> Bool,
        perform: (URLRequest, HTTPKind, Int?) -> HTTPResult,
        lockTimeout: TimeInterval
    ) -> Result<(snapshot: AuthSnapshot, posted: Bool), QuotaError> {
        switch AuthLock.acquireExclusive(home: home, timeout: lockTimeout) {
        case .failure(let err):
            if case .success(let disk) = AuthStore.readSnapshot(home: home),
               let adopted = adoptedSibling(started: creds, disk: disk)
            {
                return .success((adopted, false))
            }
            return .failure(err)
        case .success(let lock):
            defer { lock.release() }
            return refreshWhileLocked(
                home: home, creds: creds, now: now, force: force,
                grokRunning: grokRunning, perform: perform, lock: lock
            )
        }
    }

    private static func refreshWhileLocked(
        home: URL,
        creds: AuthSnapshot,
        now: Date,
        force: Bool,
        grokRunning: () -> Bool,
        perform: (URLRequest, HTTPKind, Int?) -> HTTPResult,
        lock: HeldAuthLock
    ) -> Result<(snapshot: AuthSnapshot, posted: Bool), QuotaError> {
        let latest: AuthSnapshot
        switch AuthStore.readSnapshot(home: home) {
        case .failure(let err):
            return .failure(err)
        case .success(let disk):
            if let adopted = adoptedSibling(started: creds, disk: disk) {
                return .success((adopted, false))
            }
            if !force, !AuthStore.needsRefresh(disk, now: now) {
                return .success((disk, false))
            }
            latest = disk
        }
        if !lock.inodeStillMatchesPath() {
            return .failure(.grokBusy)
        }
        guard let req = HTTPClient.refreshRequest(clientID: latest.clientID, refreshToken: latest.refreshToken) else {
            return .failure(.network)
        }
        let http = perform(req, .refreshPOST, nil)
        if http.connectionFailed { return .failure(.network) }
        if http.status == 401 { return .failure(grokRunning() ? .grokBusy : .loginExpired) }
        if !(200..<300).contains(http.status) {
            if isRefreshLoginExpired(status: http.status, body: http.body) {
                return .failure(.loginExpired)
            }
            return .failure(.network)
        }
        switch AuthStore.parseRefreshResponse(http.body, httpStatus: http.status) {
        case .failure(let err):
            return .failure(err)
        case .success(let parsed):
            let persist = AuthStore.writeIfCAS(
                home: home,
                expected: latest,
                newAccess: parsed.access,
                newRefresh: parsed.refresh,
                expiresIn: parsed.expiresIn,
                now: now
            )
            switch persist {
            case .wrote:
                var next = latest
                next.accessToken = parsed.access
                if let r = parsed.refresh { next.refreshToken = r }
                next.expiresAt = now.addingTimeInterval(parsed.expiresIn)
                return .success((next, true))
            case .casMismatch:
                switch AuthStore.readSnapshot(home: home) {
                case .success(let newer):
                    return .success((newer, true))
                case .failure(let err):
                    return .failure(err)
                }
            case .writeFailed:
                return .failure(.persistFailed)
            }
        }
    }
}
