import Darwin
import Foundation

final class HeldAuthLock {
    fileprivate let fd: Int32
    private let path: String
    private let mutex = NSLock()
    private var timer: DispatchSourceTimer?
    private var released = false

    fileprivate init(fd: Int32, path: String) {
        self.fd = fd
        self.path = path
    }

    fileprivate func startHeartbeat() {
        writeHolderLockedOrSync(alreadyLocked: false)
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
        timer.schedule(deadline: .now() + AuthLock.heartbeatInterval, repeating: AuthLock.heartbeatInterval)
        timer.setEventHandler { [weak self] in
            self?.writeHolderLockedOrSync(alreadyLocked: false)
        }
        mutex.lock()
        self.timer = timer
        mutex.unlock()
        timer.resume()
    }

    func inodeStillMatchesPath() -> Bool {
        mutex.lock()
        defer { mutex.unlock() }
        guard !released else { return false }
        return AuthLock.inodeMatches(fd: fd, path: path)
    }

    private func writeHolderLockedOrSync(alreadyLocked: Bool) {
        if !alreadyLocked { mutex.lock() }
        defer { if !alreadyLocked { mutex.unlock() } }
        guard !released else { return }
        _ = AuthLock.writeHolder(fd: fd, pid: getpid(), now: Date())
    }

    func release() {
        mutex.lock()
        timer?.cancel()
        timer = nil
        guard !released else {
            mutex.unlock()
            return
        }
        flock(fd, LOCK_UN)
        close(fd)
        released = true
        mutex.unlock()
    }

    deinit { release() }
}

enum AuthLock {
    static let acquireTimeout: TimeInterval = 25
    static let heartbeatInterval: TimeInterval = 2
    static let pollMicros: useconds_t = 50_000

    static func lockURL(home: URL) -> URL {
        home.appendingPathComponent(".grok/auth.json.lock")
    }

    static func formatHolder(pid: pid_t, now: Date) -> String {
        "\(pid):\(Int(now.timeIntervalSince1970))"
    }

    static func parseHolder(_ data: Data) -> (pid: pid_t, unix: Int)? {
        guard let text = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            let colon = text.firstIndex(of: ":")
        else {
            return nil
        }
        let pidPart = text[..<colon]
        let tsPart = text[text.index(after: colon)...]
        guard let pid = pid_t(pidPart), pid > 0, let unix = Int(tsPart) else { return nil }
        return (pid, unix)
    }

    static func isProcessAlive(_ pid: pid_t) -> Bool {
        if pid <= 0 { return false }
        if kill(pid, 0) == 0 { return true }
        return errno != ESRCH
    }

    static func inodeMatches(fd: Int32, path: String) -> Bool {
        var fdStat = stat()
        var pathStat = stat()
        guard fstat(fd, &fdStat) == 0 else { return false }
        guard stat(path, &pathStat) == 0 else { return false }
        return fdStat.st_dev == pathStat.st_dev && fdStat.st_ino == pathStat.st_ino
    }

    @discardableResult
    static func writeHolder(fd: Int32, pid: pid_t, now: Date) -> Bool {
        let payload = Array(formatHolder(pid: pid, now: now).utf8)
        let written: Int = payload.withUnsafeBytes { raw in
            guard let base = raw.bindMemory(to: UInt8.self).baseAddress else { return -1 }
            return pwrite(fd, base, payload.count, 0)
        }
        guard written == payload.count else { return false }
        guard ftruncate(fd, off_t(payload.count)) == 0 else { return false }
        return fsync(fd) == 0
    }

    static func acquireExclusive(
        home: URL,
        timeout: TimeInterval = acquireTimeout
    ) -> Result<HeldAuthLock, QuotaError> {
        let path = lockURL(home: home).path
        let deadline = DispatchTime.now() + timeout
        while DispatchTime.now() < deadline {
            let fd = open(path, O_RDWR | O_CREAT | O_CLOEXEC, 0o600)
            if fd < 0 {
                let err = errno
                if [EACCES, EISDIR, ENOTDIR, EROFS, EPERM].contains(err) {
                    return .failure(.persistFailed)
                }
                usleep(pollMicros)
                continue
            }
            if flock(fd, LOCK_EX | LOCK_NB) != 0 {
                close(fd)
                usleep(pollMicros)
                continue
            }
            if !inodeMatches(fd: fd, path: path) {
                flock(fd, LOCK_UN)
                close(fd)
                usleep(pollMicros)
                continue
            }
            let held = HeldAuthLock(fd: fd, path: path)
            held.startHeartbeat()
            return .success(held)
        }
        return .failure(.grokBusy)
    }
}
