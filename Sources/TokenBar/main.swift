import AppKit
import Foundation
import TokenBarCore

@MainActor
final class TokenBarApp: NSObject, NSApplicationDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let reader = CodexUsageReader()
    private var timer: Timer?
    private var latestSnapshot: UsageSnapshot?
    private var latestError: Error?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        if let button = statusItem.button {
            button.title = "Codex --"
            button.toolTip = "Codex token usage"
        }

        statusItem.menu = makeMenu()
        refresh()

        timer = Timer.scheduledTimer(
            timeInterval: 60,
            target: self,
            selector: #selector(refreshFromTimer),
            userInfo: nil,
            repeats: true
        )
    }

    private func refresh() {
        do {
            latestSnapshot = try reader.readSnapshot()
            latestError = nil
        } catch {
            latestSnapshot = nil
            latestError = error
        }

        statusItem.button?.title = menuBarTitle()
        statusItem.button?.toolTip = menuBarToolTip()
        statusItem.menu = makeMenu()
    }

    private func menuBarTitle() -> String {
        guard let snapshot = latestSnapshot else {
            return "Codex --"
        }

        if let primary = snapshot.latestRateLimits?.primary,
           let secondary = snapshot.latestRateLimits?.secondary {
            return "5h \(formatPercent(primary.usedPercent)) W \(formatPercent(secondary.usedPercent))"
        }

        return "5h \(formatCompactTokens(snapshot.fiveHourTokens)) W \(formatCompactTokens(snapshot.weeklyTokens))"
    }

    private func menuBarToolTip() -> String {
        guard let snapshot = latestSnapshot else {
            return latestError?.localizedDescription ?? "Codex token usage is unavailable."
        }

        return "5-hour tokens: \(formatTokens(snapshot.fiveHourTokens))\nWeekly tokens: \(formatTokens(snapshot.weeklyTokens))"
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()

        let title = NSMenuItem(title: "Codex Token Usage", action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)

        if let snapshot = latestSnapshot {
            addRateWindowItems(snapshot, to: menu)
            menu.addItem(.separator())
            menu.addItem(disabledItem("5-hour tokens: \(formatTokens(snapshot.fiveHourTokens))"))
            menu.addItem(disabledItem("Weekly tokens: \(formatTokens(snapshot.weeklyTokens))"))

            if let latest = snapshot.latestTokenUsage {
                menu.addItem(disabledItem("Latest session total: \(formatTokens(latest.totalTokens))"))
            }

            if let lastEventDate = snapshot.lastEventDate {
                menu.addItem(disabledItem("Last Codex event: \(formatDateTime(lastEventDate))"))
            } else {
                menu.addItem(disabledItem("Last Codex event: none found"))
            }

            menu.addItem(disabledItem("Files scanned: \(snapshot.filesScanned), events read: \(snapshot.eventsRead)"))
        } else {
            menu.addItem(disabledItem(latestError?.localizedDescription ?? "Unable to read Codex usage."))
        }

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Refresh Now", action: #selector(refreshFromMenu), keyEquivalent: "r", target: self))
        menu.addItem(NSMenuItem(title: "Open Codex Folder", action: #selector(openCodexFolder), keyEquivalent: "o", target: self))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Token Bar", action: #selector(quit), keyEquivalent: "q", target: self))

        return menu
    }

    private func addRateWindowItems(_ snapshot: UsageSnapshot, to menu: NSMenu) {
        guard let limits = snapshot.latestRateLimits else {
            menu.addItem(disabledItem("Rate windows: not present in latest Codex event"))
            return
        }

        if let primary = limits.primary {
            menu.addItem(disabledItem("5-hour segment: \(formatPercent(primary.usedPercent)) used"))
            menu.addItem(disabledItem("5-hour reset: \(formatReset(primary.resetsAt))"))
        } else {
            menu.addItem(disabledItem("5-hour segment: unavailable"))
        }

        if let secondary = limits.secondary {
            menu.addItem(disabledItem("Weekly segment: \(formatPercent(secondary.usedPercent)) used"))
            menu.addItem(disabledItem("Weekly reset: \(formatReset(secondary.resetsAt))"))
        } else {
            menu.addItem(disabledItem("Weekly segment: unavailable"))
        }

        if let planType = limits.planType {
            menu.addItem(disabledItem("Plan: \(planType)"))
        }
    }

    private func disabledItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    @objc private func refreshFromMenu() {
        refresh()
    }

    @objc private func refreshFromTimer() {
        refresh()
    }

    @objc private func openCodexFolder() {
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex", isDirectory: true)
        NSWorkspace.shared.open(url)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

private extension NSMenuItem {
    convenience init(title: String, action: Selector?, keyEquivalent: String, target: AnyObject?) {
        self.init(title: title, action: action, keyEquivalent: keyEquivalent)
        self.target = target
    }
}

private func formatPercent(_ value: Double) -> String {
    if value.rounded() == value {
        return "\(Int(value))%"
    }
    return "\(String(format: "%.1f", value))%"
}

private func formatTokens(_ tokens: Int) -> String {
    NumberFormatter.tokenFormatter.string(from: NSNumber(value: tokens)) ?? "\(tokens)"
}

private func formatCompactTokens(_ tokens: Int) -> String {
    let number = Double(tokens)

    if number >= 1_000_000 {
        return "\(String(format: "%.1f", number / 1_000_000))M"
    }
    if number >= 1_000 {
        return "\(String(format: "%.1f", number / 1_000))K"
    }
    return "\(tokens)"
}

private func formatReset(_ date: Date?) -> String {
    guard let date else {
        return "unknown"
    }
    return formatDateTime(date)
}

private func formatDateTime(_ date: Date) -> String {
    DateFormatter.menuDateTimeFormatter.string(from: date)
}

private extension NumberFormatter {
    static let tokenFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter
    }()
}

private extension DateFormatter {
    static let menuDateTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}

let app = NSApplication.shared
let delegate = TokenBarApp()
app.delegate = delegate
app.run()
