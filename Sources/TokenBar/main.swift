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
    private var updateState: UpdateState = .idle

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        if let button = statusItem.button {
            button.title = "Codex --"
            button.toolTip = "Codex token usage"
        }

        statusItem.menu = makeMenu()
        refreshUsage()

        timer = Timer.scheduledTimer(
            timeInterval: 60,
            target: self,
            selector: #selector(refreshFromTimer),
            userInfo: nil,
            repeats: true
        )
    }

    private func refreshUsage() {
        do {
            latestSnapshot = try reader.readSnapshot()
            latestError = nil
        } catch {
            latestSnapshot = nil
            latestError = error
        }

        render()
    }

    private func render() {
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
            statusItem.length = preferences.windowSelection == .both ? 76 : 42
            button.title = ""
            button.imagePosition = .imageOnly
            button.image = MenuBarRenderer.donutImage(
                primaryPercent: primaryPercent,
                weeklyPercent: weeklyPercent,
                selection: preferences.windowSelection
            )

        case .bar:
            statusItem.length = preferences.windowSelection == .both ? 86 : 72
            button.title = ""
            button.imagePosition = .imageOnly
            button.image = MenuBarRenderer.barImage(
                primaryPercent: primaryPercent,
                weeklyPercent: weeklyPercent,
                selection: preferences.windowSelection
            )
        }
    }

    private var primaryPercent: Double? {
        latestSnapshot?.latestRateLimits?.primary?.usedPercent
    }

    private var weeklyPercent: Double? {
        latestSnapshot?.latestRateLimits?.secondary?.usedPercent
    }

    private func menuBarTitle() -> String {
        guard let snapshot = latestSnapshot else {
            return "Codex --"
        }

        if let primary = snapshot.latestRateLimits?.primary,
           let secondary = snapshot.latestRateLimits?.secondary {
            return selectedTitle(
                fiveHourValue: formatPercent(primary.usedPercent),
                weeklyValue: formatPercent(secondary.usedPercent)
            )
        }

        return selectedTitle(
            fiveHourValue: formatCompactTokens(snapshot.fiveHourTokens),
            weeklyValue: formatCompactTokens(snapshot.weeklyTokens)
        )
    }

    private func selectedTitle(fiveHourValue: String, weeklyValue: String) -> String {
        switch preferences.windowSelection {
        case .fiveHour:
            return "5h \(fiveHourValue)"
        case .week:
            return "\(weekLabel) \(weeklyValue)"
        case .both:
            return "5h \(fiveHourValue) \(weekLabel) \(weeklyValue)"
        }
    }

    private var weekLabel: String {
        preferences.weekLabelStyle == .long ? "Week" : "W"
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

        addAppearanceItems(to: menu)
        menu.addItem(.separator())
        addInfoMenu(to: menu)
        menu.addItem(.separator())
        let updateItem = NSMenuItem(title: updateMenuTitle, action: #selector(updateTokenBar), keyEquivalent: "u", target: self)
        updateItem.isEnabled = !updateState.isRunning
        menu.addItem(updateItem)
        menu.addItem(NSMenuItem(title: "Refresh Now", action: #selector(refreshFromMenu), keyEquivalent: "r", target: self))
        menu.addItem(NSMenuItem(title: "Open Codex Folder", action: #selector(openCodexFolder), keyEquivalent: "o", target: self))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Token Bar", action: #selector(quit), keyEquivalent: "q", target: self))

        return menu
    }

    private func addInfoMenu(to menu: NSMenu) {
        let infoMenu = NSMenu()

        if let snapshot = latestSnapshot {
            addRateWindowItems(snapshot, to: infoMenu)
            infoMenu.addItem(.separator())
            infoMenu.addItem(disabledItem("5-hour tokens: \(formatTokens(snapshot.fiveHourTokens))"))
            infoMenu.addItem(disabledItem("Weekly tokens: \(formatTokens(snapshot.weeklyTokens))"))

            if let latest = snapshot.latestTokenUsage {
                infoMenu.addItem(disabledItem("Latest session total: \(formatTokens(latest.totalTokens))"))
            }

            if let lastEventDate = snapshot.lastEventDate {
                infoMenu.addItem(disabledItem("Last Codex event: \(formatDateTime(lastEventDate))"))
            } else {
                infoMenu.addItem(disabledItem("Last Codex event: none found"))
            }

            infoMenu.addItem(disabledItem("Files scanned: \(snapshot.filesScanned), events read: \(snapshot.eventsRead)"))
        } else {
            infoMenu.addItem(disabledItem(latestError?.localizedDescription ?? "Unable to read Codex usage."))
        }

        if let status = updateState.infoText {
            infoMenu.addItem(.separator())
            infoMenu.addItem(disabledItem(status))
        }

        let infoItem = NSMenuItem(title: "Info", action: nil, keyEquivalent: "")
        infoItem.submenu = infoMenu
        menu.addItem(infoItem)
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

        let windowMenu = NSMenu()
        for selection in WindowSelection.allCases {
            let item = NSMenuItem(title: selection.title, action: #selector(selectWindowSelection(_:)), keyEquivalent: "", target: self)
            item.representedObject = selection.rawValue
            item.state = preferences.windowSelection == selection ? .on : .off
            windowMenu.addItem(item)
        }

        let windowItem = NSMenuItem(title: "Usage Window", action: nil, keyEquivalent: "")
        windowItem.submenu = windowMenu
        menu.addItem(windowItem)

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

    private var updateMenuTitle: String {
        switch updateState {
        case .idle, .succeeded, .failed:
            return "Update Token Bar"
        case .running:
            return "Updating..."
        }
    }

    @objc private func refreshFromMenu() {
        refreshUsage()
    }

    @objc private func refreshFromTimer() {
        refreshUsage()
    }

    @objc private func selectMenuBarStyle(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let style = MenuBarStyle(rawValue: rawValue)
        else {
            return
        }

        preferences.menuBarStyle = style
        render()
    }

    @objc private func selectWindowSelection(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let selection = WindowSelection(rawValue: rawValue)
        else {
            return
        }

        preferences.windowSelection = selection
        render()
    }

    @objc private func selectWeekLabelStyle(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let style = WeekLabelStyle(rawValue: rawValue)
        else {
            return
        }

        preferences.weekLabelStyle = style
        render()
    }

    @objc private func toggleResetTimes() {
        preferences.showResetTimes.toggle()
        render()
    }

    @objc private func updateTokenBar() {
        guard !updateState.isRunning else {
            return
        }

        let installRoot = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".local/share/token-bar", isDirectory: true)
        let bootstrap = installRoot.appendingPathComponent("Scripts/bootstrap.sh")

        guard FileManager.default.fileExists(atPath: bootstrap.path) else {
            updateState = .failed("Install source not found. Reinstall with the bootstrap script first.")
            render()
            return
        }

        updateState = .running
        render()

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["Scripts/bootstrap.sh"]
        process.currentDirectoryURL = installRoot
        process.environment = updateEnvironment()

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = outputPipe

        process.terminationHandler = { [weak self] finishedProcess in
            let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""

            Task { @MainActor in
                self?.finishUpdate(status: finishedProcess.terminationStatus, output: output)
            }
        }

        do {
            try process.run()
        } catch {
            updateState = .failed(error.localizedDescription)
            render()
        }
    }

    private func updateEnvironment() -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        environment["TOKEN_BAR_OPEN"] = "0"
        environment["TOKEN_BAR_INSTALL_ROOT"] = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".local/share/token-bar", isDirectory: true)
            .path
        environment["TOKEN_BAR_APP_DIR"] = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Applications", isDirectory: true)
            .path
        environment["TOKEN_BAR_BIN_DIR"] = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".local/bin", isDirectory: true)
            .path
        return environment
    }

    private func finishUpdate(status: Int32, output: String) {
        if status == 0 {
            updateState = .succeeded
            render()
            relaunchAfterUpdate()
        } else {
            updateState = .failed(lastMeaningfulLine(in: output) ?? "Update failed with status \(status).")
            render()
        }
    }

    private func relaunchAfterUpdate() {
        let appPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Applications/Token Bar.app")
            .path
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "sleep 0.6; open \(shellQuoted(appPath))"]

        try? process.run()
        NSApp.terminate(nil)
    }

    private func lastMeaningfulLine(in output: String) -> String? {
        output
            .split(separator: "\n")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .last { !$0.isEmpty }
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

    var title: String {
        switch self {
        case .short:
            return "Short: W"
        case .long:
            return "Long: Week"
        }
    }
}

enum WindowSelection: String, CaseIterable {
    case fiveHour
    case week
    case both

    var title: String {
        switch self {
        case .fiveHour:
            return "5-hour"
        case .week:
            return "Week"
        case .both:
            return "Both"
        }
    }
}

enum UpdateState {
    case idle
    case running
    case succeeded
    case failed(String)

    var isRunning: Bool {
        if case .running = self {
            return true
        }
        return false
    }

    var infoText: String? {
        switch self {
        case .idle:
            return nil
        case .running:
            return "Update: running"
        case .succeeded:
            return "Update: complete"
        case let .failed(message):
            return "Update failed: \(message)"
        }
    }
}

final class TokenBarPreferences {
    private enum Key {
        static let menuBarStyle = "menuBarStyle"
        static let windowSelection = "windowSelection"
        static let weekLabelStyle = "weekLabelStyle"
        static let showResetTimes = "showResetTimes"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Key.menuBarStyle: MenuBarStyle.compactText.rawValue,
            Key.windowSelection: WindowSelection.both.rawValue,
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

    var windowSelection: WindowSelection {
        get {
            WindowSelection(rawValue: defaults.string(forKey: Key.windowSelection) ?? "") ?? .both
        }
        set {
            defaults.set(newValue.rawValue, forKey: Key.windowSelection)
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
    static func donutImage(primaryPercent: Double?, weeklyPercent: Double?, selection: WindowSelection) -> NSImage {
        let values = selectedValues(primaryPercent: primaryPercent, weeklyPercent: weeklyPercent, selection: selection)
        let size = NSSize(width: values.count == 2 ? 68 : 34, height: 22)
        let image = NSImage(size: size)

        image.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high

        for (index, value) in values.enumerated() {
            let originX = values.count == 2 ? CGFloat(index * 34) : 0
            drawDonut(value, originX: originX)
        }

        image.unlockFocus()
        image.isTemplate = false
        return image
    }

    static func barImage(primaryPercent: Double?, weeklyPercent: Double?, selection: WindowSelection) -> NSImage {
        let values = selectedValues(primaryPercent: primaryPercent, weeklyPercent: weeklyPercent, selection: selection)
        let size = NSSize(width: values.count == 2 ? 82 : 64, height: values.count == 2 ? 20 : 18)
        let image = NSImage(size: size)

        image.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high

        if values.count == 2 {
            drawBar(values[0], trackRect: NSRect(x: 17, y: 11, width: 62, height: 7), labelPrefix: "5h")
            drawBar(values[1], trackRect: NSRect(x: 17, y: 2, width: 62, height: 7), labelPrefix: "W")
        } else {
            drawBar(values[0], trackRect: NSRect(x: 3, y: 4, width: 58, height: 10), labelPrefix: nil)
        }

        image.unlockFocus()
        image.isTemplate = false
        return image
    }

    private static func drawDonut(_ value: DisplayValue, originX: CGFloat) {
        let ringRect = NSRect(x: originX + 7, y: 2, width: 18, height: 18)
        let center = NSPoint(x: ringRect.midX, y: ringRect.midY)
        let radius = ringRect.width / 2

        drawRing(center: center, radius: radius, lineWidth: 2.2, percent: clampPercent(value.percent))

        let label = percentLabel(value.percent)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: label.count > 3 ? 5.8 : 6.6, weight: .semibold),
            .foregroundColor: NSColor.labelColor
        ]
        let labelSize = label.size(withAttributes: attributes)
        label.draw(
            at: NSPoint(x: center.x - labelSize.width / 2, y: center.y - labelSize.height / 2 - 0.2),
            withAttributes: attributes
        )
    }

    private static func drawBar(_ value: DisplayValue, trackRect: NSRect, labelPrefix: String?) {
        let clamped = clampPercent(value.percent)
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

        if let labelPrefix {
            let prefixAttributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 6.2, weight: .semibold),
                .foregroundColor: NSColor.labelColor.withAlphaComponent(0.72)
            ]
            labelPrefix.draw(
                at: NSPoint(x: 2, y: trackRect.midY - 3.7),
                withAttributes: prefixAttributes
            )
        }

        let label = percentLabel(value.percent)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: trackRect.height < 8 ? 5.8 : 7, weight: .semibold),
            .foregroundColor: NSColor.labelColor
        ]
        let labelSize = label.size(withAttributes: attributes)
        label.draw(
            at: NSPoint(x: trackRect.midX - labelSize.width / 2, y: trackRect.midY - labelSize.height / 2 - 0.1),
            withAttributes: attributes
        )
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

    private static func selectedValues(
        primaryPercent: Double?,
        weeklyPercent: Double?,
        selection: WindowSelection
    ) -> [DisplayValue] {
        switch selection {
        case .fiveHour:
            return [DisplayValue(label: "5h", percent: primaryPercent)]
        case .week:
            return [DisplayValue(label: "W", percent: weeklyPercent)]
        case .both:
            return [
                DisplayValue(label: "5h", percent: primaryPercent),
                DisplayValue(label: "W", percent: weeklyPercent)
            ]
        }
    }
}

private struct DisplayValue {
    var label: String
    var percent: Double?
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

private func shellQuoted(_ value: String) -> String {
    "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
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
