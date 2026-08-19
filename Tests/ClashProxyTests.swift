import Foundation

enum ClashProxyTests {
    static func run() -> Int {
        var failed = 0
        failed += check("clashx known mixed port") {
            let sample = """
            COMMAND   PID USER   FD   TYPE             DEVICE SIZE/OFF NODE NAME
            ClashX  21927 wangqw   11u  IPv6 0x51  0t0  TCP *:7890 (LISTEN)
            clash-ver 22037 wangqw   14u  IPv4 0xcf  0t0  TCP 127.0.0.1:33331 (LISTEN)
            """
            return ClashProxy.bestPort(fromLsof: sample) == 7890
        }
        failed += check("7897 beats star socks") {
            let sample = """
            COMMAND   PID USER   FD   TYPE DEVICE SIZE/OFF NODE NAME
            ClashX  1 wangqw   11u  IPv4 0x0  0t0  TCP *:7891 (LISTEN)
            ClashX  1 wangqw   12u  IPv4 0x0  0t0  TCP 127.0.0.1:7897 (LISTEN)
            """
            return ClashProxy.bestPort(fromLsof: sample) == 7897
        }
        failed += check("last host:port field") {
            ClashProxy.addressField(in: ["ClashX", "1", "u", "TCP", "*:7897", "(LISTEN)"]) == "*:7897"
        }
        return failed
    }

    private static func check(_ name: String, _ body: () -> Bool) -> Int {
        if body() {
            print("ok  \(name)")
            return 0
        }
        print("FAIL \(name)")
        return 1
    }
}
