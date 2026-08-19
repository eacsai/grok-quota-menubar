import Darwin
import Foundation

enum GrokProcess {
    static func officialGrokRunning(
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        selfPID: pid_t = getpid()
    ) -> Bool {
        let grokHome = home.appendingPathComponent(".grok", isDirectory: true)
        let bin = grokHome.appendingPathComponent("bin/grok").resolvingSymlinksInPath().path
        let downloads = grokHome.appendingPathComponent("downloads", isDirectory: true).path
        return anyOfficialGrokProcess(binRealPath: bin, downloadsDir: downloads, selfPID: selfPID)
    }

    static func isOfficialGrokPath(_ path: String, binRealPath: String, downloadsDir: String) -> Bool {
        if path == binRealPath { return true }
        let name = (path as NSString).lastPathComponent
        guard name.hasPrefix("grok-") else { return false }
        let parent = (path as NSString).deletingLastPathComponent
        return parent == downloadsDir
    }

    static func anyOfficialGrokProcess(binRealPath: String, downloadsDir: String, selfPID: pid_t) -> Bool {
        let hint = proc_listpids(UInt32(PROC_ALL_PIDS), 0, nil, 0)
        guard hint > 0 else { return true }
        var byteCap = hint * 2 + Int32(64 * MemoryLayout<pid_t>.size)
        for _ in 0..<3 {
            let count = Int(byteCap) / MemoryLayout<pid_t>.size
            var pids = [pid_t](repeating: 0, count: max(count, 1))
            let written = proc_listpids(UInt32(PROC_ALL_PIDS), 0, &pids, byteCap)
            guard written > 0 else { return true }
            if written == byteCap {
                byteCap *= 2
                continue
            }
            let n = Int(written) / MemoryLayout<pid_t>.size
            for i in 0..<n {
                let pid = pids[i]
                if pid <= 0 || pid == selfPID { continue }
                guard let path = path(for: pid) else { continue }
                if isOfficialGrokPath(path, binRealPath: binRealPath, downloadsDir: downloadsDir) {
                    return true
                }
            }
            return false
        }
        return true
    }

    private static func path(for pid: pid_t) -> String? {
        var buf = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
        let n = proc_pidpath(pid, &buf, UInt32(buf.count))
        guard n > 0 else { return nil }
        return String(cString: buf)
    }
}
