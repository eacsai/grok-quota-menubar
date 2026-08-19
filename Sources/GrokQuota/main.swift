import AppKit
import Foundation

let args = CommandLine.arguments
if args.contains("--once") {
    let json = args.contains("--json")
    let outcome = BillingClient.fetch()
    if json {
        printOnceJSON(outcome)
    } else if let snap = outcome.snapshot {
        FileHandle.standardError.write(Data("Grok \(snap.remainingPercent)% · \(snap.compactReset)\n".utf8))
    } else {
        FileHandle.standardError.write(Data("\((outcome.error ?? .network).rawValue)\n".utf8))
        exit(1)
    }
    exit(outcome.snapshot == nil ? 1 : 0)
}

let app = NSApplication.shared
let delegate = MenuBarApp()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()

func printOnceJSON(_ outcome: FetchOutcome) {
    var obj: [String: Any] = [:]
    if let snap = outcome.snapshot {
        obj["ok"] = true
        obj["remaining_percent"] = snap.remainingPercent
        obj["used_percent"] = snap.usedPercent
        obj["period_type"] = snap.periodType
        obj["reset_at_local"] = snap.fullReset
    } else {
        obj["ok"] = false
        obj["error_class"] = (outcome.error ?? .network).rawValue
    }
    if let data = try? JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys]),
       let text = String(data: data, encoding: .utf8)
    {
        print(text)
    }
}

final class MenuBarApp: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var item: NSStatusItem!
    private var menu: NSMenu!
    private let work = DispatchQueue(label: "ai.xai.grok-quota")
    private let pendingLock = NSLock()
    private var inFlight = false
    private var lastStart: DispatchTime?
    private var lastFinish: DispatchTime?
    private var pendingReasons: [KickReason] = []

    private enum KickReason {
        case timer
        case menu
        case userRefresh
        case wake
    }
    private var snapshot: QuotaSnapshot?
    private var lastError: QuotaError?
    private var stale = false

    private let usedItem = NSMenuItem(title: "已用 —", action: nil, keyEquivalent: "")
    private let remainItem = NSMenuItem(title: "剩余 —", action: nil, keyEquivalent: "")
    private let periodItem = NSMenuItem(title: "周期 —", action: nil, keyEquivalent: "")
    private let resetItem = NSMenuItem(title: "重置 —", action: nil, keyEquivalent: "")
    private let statusItem = NSMenuItem(title: "正在更新", action: nil, keyEquivalent: "")
    private let fetchedItem = NSMenuItem(title: "更新于 —", action: nil, keyEquivalent: "")

    func applicationDidFinishLaunching(_ notification: Notification) {
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "Grok …"
        applyYellowTitle("Grok …")

        menu = NSMenu()
        menu.delegate = self
        for entry in [usedItem, remainItem, periodItem, resetItem, fetchedItem, statusItem] {
            entry.isEnabled = false
            menu.addItem(entry)
        }
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "立即刷新", action: #selector(refreshNow), keyEquivalent: "r"))
        menu.addItem(NSMenuItem(title: "打开 Usage", action: #selector(openUsage), keyEquivalent: "o"))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "退出", action: #selector(quit), keyEquivalent: "q"))
        item.menu = menu

        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(didWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
        Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            self?.kick(reason: .timer)
        }
        kick(reason: .wake)
    }

    func menuWillOpen(_ menu: NSMenu) {
        kick(reason: .menu)
    }

    @objc private func didWake() { kick(reason: .wake) }
    @objc private func refreshNow() { kick(reason: .userRefresh) }

    @objc private func openUsage() {
        if let url = URL(string: "https://grok.com/?_s=usage") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func kick(reason: KickReason) {
        pendingLock.lock()
        pendingReasons.append(reason)
        pendingLock.unlock()
        work.async { [weak self] in
            self?.drain()
        }
    }

    private func drain() {
        if inFlight { return }
        pendingLock.lock()
        let reasons = pendingReasons
        pendingReasons.removeAll()
        pendingLock.unlock()
        guard !reasons.isEmpty else { return }
        let wake = reasons.contains(.wake)
        let mark = lastFinish ?? lastStart
        if !wake, let last = mark,
           DispatchTime.now().uptimeNanoseconds &- last.uptimeNanoseconds < 30_000_000_000
        {
            return
        }
        inFlight = true
        lastStart = DispatchTime.now()
        DispatchQueue.main.async { self.renderRefreshing() }
        let outcome = BillingClient.fetch()
        lastFinish = DispatchTime.now()
        inFlight = false
        DispatchQueue.main.async { self.apply(outcome) }
        pendingLock.lock()
        let more = !pendingReasons.isEmpty
        pendingLock.unlock()
        if more { drain() }
    }

    private func renderRefreshing() {
        if snapshot == nil {
            applyYellowTitle("Grok …")
            statusItem.title = "正在更新"
        }
    }

    private func apply(_ outcome: FetchOutcome) {
        let now = Date()
        if let snap = outcome.snapshot {
            snapshot = snap
            lastError = nil
            stale = false
        } else {
            lastError = outcome.error
            if let snap = snapshot {
                let ended = now >= snap.periodEnd.addingTimeInterval(QuotaParser.skew)
                stale = true
                if ended {
                    lastError = .periodEnded
                }
            }
        }
        render()
    }

    private func render() {
        let now = Date()
        if let snap = snapshot {
            let ended = now >= snap.periodEnd.addingTimeInterval(QuotaParser.skew)
            let tooOld = snap.staleAge(wallNow: now, monoNow: .now()) > 6 * 3600
            usedItem.title = String(format: "已用 %.1f%%", snap.usedPercent)
            remainItem.title = "剩余 \(snap.remainingPercent)%"
            periodItem.title = snap.periodType
            resetItem.title = "重置 \(snap.fullReset)"
            fetchedItem.title = "更新于 \(timeOnly(snap.fetchedAt))"
            if ended {
                applyYellowTitle("Grok ?")
                statusItem.title = QuotaError.periodEnded.rawValue
            } else if stale && tooOld {
                applyYellowTitle("Grok ?")
                statusItem.title = "数据可能过期 · \((lastError ?? .network).rawValue)"
            } else if stale {
                applyYellowTitle("Grok \(snap.remainingPercent)% · \(snap.compactReset)")
                statusItem.title = "数据可能过期 · \((lastError ?? .network).rawValue)"
            } else {
                applyYellowTitle("Grok \(snap.remainingPercent)% · \(snap.compactReset)")
                statusItem.title = "已更新"
            }
        } else {
            applyYellowTitle("Grok ?")
            usedItem.title = "已用 —"
            remainItem.title = "剩余 —"
            periodItem.title = "周期 —"
            resetItem.title = "重置 —"
            fetchedItem.title = "更新于 —"
            statusItem.title = (lastError ?? .network).rawValue
        }
    }

    private func applyYellowTitle(_ text: String) {
        let color = NSColor.systemCyan
        let attrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: color,
            .font: NSFont.menuBarFont(ofSize: 0),
        ]
        item.button?.attributedTitle = NSAttributedString(string: text, attributes: attrs)
    }

    private func timeOnly(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale.current
        f.timeStyle = .short
        f.dateStyle = .none
        return f.string(from: date)
    }
}
