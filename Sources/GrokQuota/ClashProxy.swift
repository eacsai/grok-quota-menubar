import Foundation

enum ClashProxy {
    private static let skipPorts: Set<Int> = [9090, 9091, 9097, 33331]

    static func discoverMixedPort() -> Int? {
        if let text = lsofListen(), let ranked = bestPort(fromLsof: text), portOK(ranked) {
            return ranked
        }
        return fallbackPort()
    }

    static func bestPort(fromLsof text: String) -> Int? {
        var best: (rank: Int, port: Int)?
        for line in text.split(whereSeparator: \.isNewline) {
            let cols = line.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
            guard cols.count >= 2 else { continue }
            let command = cols[0]
            guard let addr = addressField(in: cols), let port = port(of: addr), !skipPorts.contains(port) else {
                continue
            }
            let star = addr.hasPrefix("*:")
            let loop = addr.hasPrefix("127.0.0.1:")
            guard star || loop else { continue }
            let rank: Int?
            if command.range(of: "ClashX", options: .caseInsensitive) != nil {
                if port == 7897 { rank = 1 }
                else if port == 7890 { rank = 2 }
                else { rank = nil }
            } else if command.range(of: "verge", options: .caseInsensitive) != nil {
                rank = nil
            } else if command.range(of: "mihomo", options: .caseInsensitive) != nil
                || command.range(of: "clash", options: .caseInsensitive) != nil
            {
                if port == 7897 { rank = 3 }
                else if port == 7890 { rank = 4 }
                else { rank = nil }
            } else {
                rank = nil
            }
            if let rank {
                if best == nil || rank < best!.rank {
                    best = (rank, port)
                }
            }
        }
        return best?.port
    }

    private static func fallbackPort() -> Int? {
        if portOK(7897) { return 7897 }
        if portOK(7890) { return 7890 }
        return nil
    }

    static func addressField(in cols: [String]) -> String? {
        cols.reversed().first { port(of: $0) != nil }
    }

    static func port(of addr: String) -> Int? {
        let token = addr.split(whereSeparator: { $0 == " " }).first.map(String.init) ?? addr
        guard let idx = token.lastIndex(of: ":") else { return nil }
        return Int(token[token.index(after: idx)...])
    }

    private static func portOK(_ port: Int) -> Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/nc")
        task.arguments = ["-z", "-G", "1", "127.0.0.1", String(port)]
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        do {
            try task.run()
            task.waitUntilExit()
            return task.terminationStatus == 0
        } catch {
            return false
        }
    }

    private static func lsofListen() -> String? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        task.arguments = ["-iTCP", "-sTCP:LISTEN", "-P", "-n"]
        let out = Pipe()
        task.standardOutput = out
        task.standardError = FileHandle.nullDevice
        do {
            try task.run()
            let data = out.fileHandleForReading.readDataToEndOfFile()
            task.waitUntilExit()
            let text = String(data: data, encoding: .utf8)
            guard let text, !text.isEmpty else { return nil }
            if bestPort(fromLsof: text) != nil { return text }
            guard task.terminationStatus == 0 else { return nil }
            return text
        } catch {
            return nil
        }
    }
}
