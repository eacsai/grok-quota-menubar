import Darwin
import Foundation

enum AuthLockTests {
    static func run() -> Int {
        var failed = 0
        failed += check("holder format pid:unix") {
            let text = AuthLock.formatHolder(pid: 39386, now: Date(timeIntervalSince1970: 1_787_132_569))
            return text == "39386:1787132569" && AuthLock.parseHolder(Data(text.utf8))?.pid == 39386
        }
        failed += check("parse rejects garbage") {
            AuthLock.parseHolder(Data("not-a-lock".utf8)) == nil
        }
        failed += check("self pid is alive") {
            AuthLock.isProcessAlive(getpid())
        }
        failed += check("pid 1:999999999 is not treated as parse fail") {
            AuthLock.parseHolder(Data("1:999999999".utf8))?.pid == 1
        }
        failed += check("exclusive lock writes holder and blocks sibling") {
            let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(
                "grok-quota-lock-\(UUID().uuidString)", isDirectory: true
            )
            try FileManager.default.createDirectory(at: tmp.appendingPathComponent(".grok"), withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: tmp) }
            switch AuthLock.acquireExclusive(home: tmp, timeout: 1) {
            case .failure:
                return false
            case .success(let held):
                defer { held.release() }
                let raw = try Data(contentsOf: AuthLock.lockURL(home: tmp))
                guard let holder = AuthLock.parseHolder(raw), holder.pid == getpid() else { return false }
                return true
            }
        }
        failed += check("other process lock makes acquire time out") {
            let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(
                "grok-quota-lock2-\(UUID().uuidString)", isDirectory: true
            )
            try FileManager.default.createDirectory(at: tmp.appendingPathComponent(".grok"), withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: tmp) }
            let child = try holdLockInChild(tmp, seconds: 3)
            defer { child.terminate() }
            guard waitUntilChildHoldsLock(home: tmp) else { return false }
            switch AuthLock.acquireExclusive(home: tmp, timeout: 0.3) {
            case .failure(.grokBusy):
                return true
            default:
                return false
            }
        }
        failed += check("heartbeat refreshes holder unix while held 3s") {
            let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(
                "grok-quota-hb-\(UUID().uuidString)", isDirectory: true
            )
            try FileManager.default.createDirectory(at: tmp.appendingPathComponent(".grok"), withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: tmp) }
            switch AuthLock.acquireExclusive(home: tmp, timeout: 1) {
            case .failure:
                return false
            case .success(let held):
                defer { held.release() }
                let first = AuthLock.parseHolder(try Data(contentsOf: AuthLock.lockURL(home: tmp)))
                Thread.sleep(forTimeInterval: 3.2)
                let second = AuthLock.parseHolder(try Data(contentsOf: AuthLock.lockURL(home: tmp)))
                guard let first, let second else { return false }
                return second.unix >= first.unix + 1 && held.inodeStillMatchesPath()
            }
        }
        failed += check("adopt when disk refresh differs") {
            let id = "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
            let started = AuthSnapshot(
                entryKey: "https://auth.x.ai::\(id)",
                clientID: id,
                accessToken: "tok-old",
                refreshToken: "ref-old",
                expiresAt: Date()
            )
            var disk = started
            disk.refreshToken = "ref-sibling"
            disk.accessToken = "tok-sibling"
            return BillingClient.adoptedSibling(started: started, disk: disk)?.refreshToken == "ref-sibling"
                && BillingClient.adoptedSibling(started: started, disk: started) == nil
        }
        return failed
    }

    static func holdLockInChild(_ home: URL, seconds: Double) throws -> Process {
        let path = AuthLock.lockURL(home: home).path
        // Apple CLT /usr/bin/python3 is Python.app and can SIGTRAP a crash
        // dialog. /usr/bin/perl is a plain binary with flock.
        let script = #"use Fcntl qw(:flock); open(my $fh, ">>", $ARGV[0]) or exit 1; flock($fh, LOCK_EX) or exit 1; sleep($ARGV[1]);"#
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        task.arguments = ["-e", script, "--", path, String(max(1, Int(seconds.rounded(.up))))]
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        try task.run()
        usleep(50_000)
        return task
    }

    static func waitUntilChildHoldsLock(home: URL, timeout: TimeInterval = 1.5) -> Bool {
        let path = AuthLock.lockURL(home: home).path
        let deadline = DispatchTime.now() + timeout
        while DispatchTime.now() < deadline {
            let fd = open(path, O_RDWR | O_CLOEXEC)
            if fd >= 0 {
                let busy = flock(fd, LOCK_EX | LOCK_NB) != 0
                if !busy { flock(fd, LOCK_UN) }
                close(fd)
                if busy { return true }
            }
            usleep(50_000)
        }
        return false
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
