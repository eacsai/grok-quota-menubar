import Foundation

enum GrokProcessTests {
    static func run() -> Int {
        let home = "/Users/demo/.grok"
        let bin = "\(home)/downloads/grok-1.0.5-macos-aarch64"
        let downloads = "\(home)/downloads"
        let ok = GrokProcess.isOfficialGrokPath(bin, binRealPath: bin, downloadsDir: downloads)
            && GrokProcess.isOfficialGrokPath(
                "\(home)/downloads/grok-1.0.5-macos-aarch64",
                binRealPath: bin,
                downloadsDir: downloads
            )
            && !GrokProcess.isOfficialGrokPath(
                "/usr/local/bin/grok",
                binRealPath: bin,
                downloadsDir: downloads
            )
            && !GrokProcess.isOfficialGrokPath(
                "/Applications/GrokQuota.app/Contents/MacOS/GrokQuota",
                binRealPath: bin,
                downloadsDir: downloads
            )
        if ok {
            print("ok  grok path matcher")
            return 0
        }
        print("FAIL grok path matcher")
        return 1
    }
}
