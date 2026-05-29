import AppKit
import Foundation
import TokenBarCore

@MainActor
final class TokenBarApp: NSObject, NSApplicationDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let reader = CodexUsageReader()
    private let preferences = TokenBarPreferences()
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

        applyMenuBarPresentation()
        statusItem.button?.toolTip = menuBarToolTip()
        statusItem.menu = makeMenu()
    }

    private func applyMenuBarPresentation() {
        guard let button = statusItem.button else {
            return
        }

        switch preferences.menuBarStyle {
        case .compactText:
            statusItem.length = NSStatusItem.variableLength
            button.image = nil
            button.imagePosition = .noImage
            button.title = menuBarTitle()

        case .donut:
            statusItem.length = 42
            button.title = ""
            button.imagePosition = .imageOnly
            button.image = MenuBarRenderer.donutImage(percent: primaryPercent)

        case .bar:
            statusItem.length = 72
            button.title = ""
            button.imagePosition = .imageOnly
            button.image = MenuBarRenderer.barImage(percent: primaryPercent)
        }
    }

    private var primaryPercent: Double? {
        latestSnapshot?.latestRateLimits?.primary?.usedPercent
    }

    private func menuBarTitle() -> String {
        guard let snapshot = latestSnapshot else {
            return "Codex --"
        }

        if let primary = snapshot.latestRateLimits?.primary,
           let secondary = snapshot.latestRateLimits?.secondary {
            return "5h \(formatPercent(primary.usedPercent))\(weekTitle(percent: secondary.usedPercent))"
        }

        return "5h \(formatCompactTokens(snapshot.fiveHourTokens))\(weekTitle(tokens: snapshot.weeklyTokens))"
    }

    private func weekTitle(percent: Double) -> String {
        switch preferences.weekLabelStyle {
        case .hidden:
            return ""
        case .short:
            return " W \(formatPercent(percent))"
        case .long:
            return " Week \(formatPercent(percent))"
        }
    }

    private func weekTitle(tokens: Int) -> String {
        switch preferences.weekLabelStyle {
        case .hidden:
            return ""
        case .short:
            return " W \(formatCompactTokens(tokens))"
        case .long:
            return " Week \(formatCompactTokens(tokens))"
        }
    }

    private func menuBarToolTip() -> String {
        guard let snapshot = latestSnapshot else {
            return latestError?.localizedDescription ?? "Codex token usage is unavailable."
        }

        var lines = [
            "5-hour tokens: \(formatTokens(snapshot.fiveHourTokens))",
            "Weekly tokens: \(formatTokens(snapshot.weeklyTokens))"
        ]

        if preferences.showResetTimes {
            if let primaryReset = snapshot.latestRateLimits?.primary?.resetsAt {
                lines.append("5-hour reset: \(formatDateTime(primaryReset))")
            }
            if let weeklyReset = snapshot.latestRateLimits?.secondary?.resetsAt {
                lines.append("Weekly reset: \(formatDateTime(weeklyReset))")
            }
        }

        return lines.joined(separator: "\n")
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
        addAppearanceItems(to: menu)
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
            if preferences.showResetTimes {
                menu.addItem(disabledItem("5-hour reset: \(formatReset(primary.resetsAt))"))
            }
        } else {
            menu.addItem(disabledItem("5-hour segment: unavailable"))
        }

        if let secondary = limits.secondary {
            menu.addItem(disabledItem("Weekly segment: \(formatPercent(secondary.usedPercent)) used"))
            if preferences.showResetTimes {
                menu.addItem(disabledItem("Weekly reset: \(formatReset(secondary.resetsAt))"))
            }
        } else {
            menu.addItem(disabledItem("Weekly segment: unavailable"))
        }

        if let planType = limits.planType {
            menu.addItem(disabledItem("Plan: \(planType)"))
        }
    }

    private func addAppearanceItems(to menu: NSMenu) {
        let styleMenu = NSMenu()
        for style in MenuBarStyle.allCases {
            let item = NSMenuItem(title: style.title, action: #selector(selectMenuBarStyle(_:)), keyEquivalent: "", target: self)
            item.representedObject = style.rawValue
            item.state = preferences.menuBarStyle == style ? .on : .off
            styleMenu.addItem(item)
        }

        let styleItem = NSMenuItem(title: "Menu Bar Style", action: nil, keyEquivalent: "")
        styleItem.submenu = styleMenu
        menu.addItem(styleItem)

        let weekMenu = NSMenu()
        for labelStyle in WeekLabelStyle.allCases {
            let item = NSMenuItem(title: labelStyle.title, action: #selector(selectWeekLabelStyle(_:)), keyEquivalent: "", target: self)
            item.representedObject = labelStyle.rawValue
            item.state = preferences.weekLabelStyle == labelStyle ? .on : .off
            weekMenu.addItem(item)
        }

        let weekItem = NSMenuItem(title: "Week Label", action: nil, keyEquivalent: "")
        weekItem.submenu = weekMenu
        menu.addItem(weekItem)

        let resetItem = NSMenuItem(title: "Show Reset Times", action: #selector(toggleResetTimes), keyEquivalent: "", target: self)
        resetItem.state = preferences.showResetTimes ? .on : .off
        menu.addItem(resetItem)
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

    @objc private func selectMenuBarStyle(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let style = MenuBarStyle(rawValue: rawValue)
        else {
            return
        }

        preferences.menuBarStyle = style
        refresh()
    }

    @objc private func selectWeekLabelStyle(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let style = WeekLabelStyle(rawValue: rawValue)
        else {
            return
        }

        preferences.weekLabelStyle = style
        refresh()
    }

    @objc private func toggleResetTimes() {
        preferences.showResetTimes.toggle()
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

enum MenuBarStyle: String, CaseIterable {
    case compactText
    case donut
    case bar

    var title: String {
        switch self {
        case .compactText:
            return "Compact Text"
        case .donut:
            return "Donut"
        case .bar:
            return "Progress Bar"
        }
    }
}

enum WeekLabelStyle: String, CaseIterable {
    case short
    case long
    case hidden

    var title: String {
        switch self {
        case .short:
            return "Short: W"
        case .long:
            return "Long: Week"
        case .hidden:
            return "Hidden"
        }
    }
}

final class TokenBarPreferences {
    private enum Key {
        static let menuBarStyle = "menuBarStyle"
        static let weekLabelStyle = "weekLabelStyle"
        static let showResetTimes = "showResetTimes"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Key.menuBarStyle: MenuBarStyle.compactText.rawValue,
            Key.weekLabelStyle: WeekLabelStyle.short.rawValue,
            Key.showResetTimes: true
        ])
    }

    var menuBarStyle: MenuBarStyle {
        get {
            MenuBarStyle(rawValue: defaults.string(forKey: Key.menuBarStyle) ?? "") ?? .compactText
        }
        set {
            defaults.set(newValue.rawValue, forKey: Key.menuBarStyle)
        }
    }

    var weekLabelStyle: WeekLabelStyle {
        get {
            WeekLabelStyle(rawValue: defaults.string(forKey: Key.weekLabelStyle) ?? "") ?? .short
        }
        set {
            defaults.set(newValue.rawValue, forKey: Key.weekLabelStyle)
        }
    }

    var showResetTimes: Bool {
        get {
            defaults.bool(forKey: Key.showResetTimes)
        }
        set {
            defaults.set(newValue, forKey: Key.showResetTimes)
        }
    }
}

enum MenuBarRenderer {
    static func donutImage(percent: Double?) -> NSImage {
        let size = NSSize(width: 34, height: 22)
        let image = NSImage(size: size)

        image.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high

        let clamped = clampPercent(percent)
        let ringRect = NSRect(x: 7, y: 2, width: 18, height: 18)
        let center = NSPoint(x: ringRect.midX, y: ringRect.midY)
        let radius = ringRect.width / 2

        drawRing(center: center, radius: radius, lineWidth: 2.2, percent: clamped)

        let label = percentLabel(percent)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: label.count > 3 ? 5.8 : 6.6, weight: .semibold),
            .foregroundColor: NSColor.labelColor
        ]
        let labelSize = label.size(withAttributes: attributes)
        label.draw(
            at: NSPoint(x: center.x - labelSize.width / 2, y: center.y - labelSize.height / 2 - 0.2),
            withAttributes: attributes
        )

        image.unlockFocus()
        image.isTemplate = false
        return image
    }

    static func barImage(percent: Double?) -> NSImage {
        let size = NSSize(width: 64, height: 18)
        let image = NSImage(size: size)

        image.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high

        let clamped = clampPercent(percent)
        let trackRect = NSRect(x: 3, y: 4, width: 58, height: 10)
        let radius = trackRect.height / 2
        let trackPath = NSBezierPath(roundedRect: trackRect, xRadius: radius, yRadius: radius)

        NSColor.separatorColor.withAlphaComponent(0.58).setFill()
        trackPath.fill()

        let fillWidth = max(trackRect.height, trackRect.width * clamped)
        let fillRect = NSRect(x: trackRect.minX, y: trackRect.minY, width: fillWidth, height: trackRect.height)

        NSGraphicsContext.saveGraphicsState()
        trackPath.addClip()
        NSColor.controlAccentColor.setFill()
        NSBezierPath(rect: fillRect).fill()
        NSGraphicsContext.restoreGraphicsState()

        NSColor.labelColor.withAlphaComponent(0.65).setStroke()
        trackPath.lineWidth = 0.6
        trackPath.stroke()

        let label = percentLabel(percent)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 7, weight: .semibold),
            .foregroundColor: NSColor.labelColor
        ]
        let labelSize = label.size(withAttributes: attributes)
        label.draw(
            at: NSPoint(x: trackRect.midX - labelSize.width / 2, y: trackRect.midY - labelSize.height / 2 - 0.1),
            withAttributes: attributes
        )

        image.unlockFocus()
        image.isTemplate = false
        return image
    }

    private static func drawRing(center: NSPoint, radius: CGFloat, lineWidth: CGFloat, percent: Double) {
        let basePath = NSBezierPath()
        basePath.appendArc(
            withCenter: center,
            radius: radius,
            startAngle: 0,
            endAngle: 360,
            clockwise: false
        )
        basePath.lineWidth = lineWidth
        NSColor.separatorColor.withAlphaComponent(0.72).setStroke()
        basePath.stroke()

        guard percent > 0 else {
            return
        }

        let progressPath = NSBezierPath()
        progressPath.appendArc(
            withCenter: center,
            radius: radius,
            startAngle: 90,
            endAngle: 90 - CGFloat(percent * 360),
            clockwise: true
        )
        progressPath.lineWidth = lineWidth
        progressPath.lineCapStyle = .round
        NSColor.controlAccentColor.setStroke()
        progressPath.stroke()
    }

    private static func clampPercent(_ percent: Double?) -> Double {
        min(max((percent ?? 0) / 100, 0), 1)
    }

    private static func percentLabel(_ percent: Double?) -> String {
        guard let percent else {
            return "--"
        }
        return "\(Int(percent.rounded()))%"
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
