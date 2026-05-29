import Foundation
import TokenBarCore

enum TokenBarCLI {
    static func main(arguments: [String]) -> Int32 {
        let command = arguments.dropFirst().first ?? "status"

        do {
            switch command {
            case "status":
                let snapshot = try CodexUsageReader().readSnapshot()
                print(renderStatus(snapshot))
                return 0

            case "json":
                let snapshot = try CodexUsageReader().readSnapshot()
                print(try renderJSON(snapshot))
                return 0

            case "launch":
                return launchApp()

            case "auth":
                return authStatus()

            case "doctor":
                return doctor()

            case "help", "-h", "--help":
                print(helpText)
                return 0

            default:
                print("Unknown command: \(command)\n")
                print(helpText)
                return 64
            }
        } catch {
            fputs("tokenbar: \(error.localizedDescription)\n", stderr)
            return 1
        }
    }

    private static func renderStatus(_ snapshot: UsageSnapshot) -> String {
        var lines: [String] = []

        if let primary = snapshot.latestRateLimits?.primary {
            lines.append("5-hour segment: \(formatPercent(primary.usedPercent)) used")
            lines.append("5-hour reset: \(formatDate(primary.resetsAt))")
        } else {
            lines.append("5-hour segment: unavailable")
        }

        if let secondary = snapshot.latestRateLimits?.secondary {
            lines.append("Weekly segment: \(formatPercent(secondary.usedPercent)) used")
            lines.append("Weekly reset: \(formatDate(secondary.resetsAt))")
        } else {
            lines.append("Weekly segment: unavailable")
        }

        lines.append("5-hour tokens: \(formatTokens(snapshot.fiveHourTokens))")
        lines.append("Weekly tokens: \(formatTokens(snapshot.weeklyTokens))")

        if let latest = snapshot.latestTokenUsage {
            lines.append("Latest session total: \(formatTokens(latest.totalTokens))")
        }

        if let plan = snapshot.latestRateLimits?.planType {
            lines.append("Plan: \(plan)")
        }

        lines.append("Last Codex event: \(formatDate(snapshot.lastEventDate))")
        lines.append("Files scanned: \(snapshot.filesScanned)")
        lines.append("Events read: \(snapshot.eventsRead)")

        return lines.joined(separator: "\n")
    }

    private static func renderJSON(_ snapshot: UsageSnapshot) throws -> String {
        var object: [String: Any] = [
            "as_of": isoString(snapshot.asOf),
            "five_hour_tokens": snapshot.fiveHourTokens,
            "weekly_tokens": snapshot.weeklyTokens,
            "files_scanned": snapshot.filesScanned,
            "events_read": snapshot.eventsRead
        ]

        if let lastEventDate = snapshot.lastEventDate {
            object["last_event_at"] = isoString(lastEventDate)
        }

        if let latest = snapshot.latestTokenUsage {
            object["latest_token_usage"] = [
                "total_tokens": latest.totalTokens,
                "input_tokens": latest.inputTokens,
                "cached_input_tokens": latest.cachedInputTokens,
                "output_tokens": latest.outputTokens,
                "reasoning_output_tokens": latest.reasoningOutputTokens
            ]
        }

        if let limits = snapshot.latestRateLimits {
            var rateLimits: [String: Any] = [:]

            if let limitID = limits.limitID {
                rateLimits["limit_id"] = limitID
            }
            if let planType = limits.planType {
                rateLimits["plan_type"] = planType
            }
            if let primary = limits.primary {
                rateLimits["primary"] = jsonWindow(primary)
            }
            if let secondary = limits.secondary {
                rateLimits["secondary"] = jsonWindow(secondary)
            }

            object["rate_limits"] = rateLimits
        }

        let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    private static func jsonWindow(_ window: RateWindow) -> [String: Any] {
        var object: [String: Any] = [
            "used_percent": window.usedPercent,
            "window_minutes": window.windowMinutes
        ]

        if let resetsAt = window.resetsAt {
            object["resets_at"] = isoString(resetsAt)
        }

        return object
    }

    private static func launchApp() -> Int32 {
        let candidates = [
            "/Applications/Token Bar.app",
            "\(FileManager.default.homeDirectoryForCurrentUser.path)/Applications/Token Bar.app",
            "\(FileManager.default.currentDirectoryPath)/dist/Token Bar.app"
        ]

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")

        if let appPath = candidates.first(where: FileManager.default.fileExists(atPath:)) {
            process.arguments = [appPath]
        } else {
            process.arguments = ["-a", "Token Bar"]
        }

        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus
        } catch {
            fputs("tokenbar: unable to launch Token Bar: \(error.localizedDescription)\n", stderr)
            return 1
        }
    }

    private static func doctor() -> Int32 {
        let codexDirectory = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex")
        let sessionsDirectory = codexDirectory.appendingPathComponent("sessions")

        print("Codex directory: \(codexDirectory.path)")
        print("Codex directory exists: \(FileManager.default.fileExists(atPath: codexDirectory.path) ? "yes" : "no")")
        print("Sessions directory exists: \(FileManager.default.fileExists(atPath: sessionsDirectory.path) ? "yes" : "no")")

        do {
            let snapshot = try CodexUsageReader().readSnapshot()
            print("Token events found: \(snapshot.eventsRead)")
            print("Last Codex event: \(formatDate(snapshot.lastEventDate))")
            return snapshot.eventsRead > 0 ? 0 : 1
        } catch {
            print("Usage read: \(error.localizedDescription)")
            return 1
        }
    }

    private static var helpText: String {
        """
        Usage: tokenbar <command>

        Commands:
          status   Print Codex 5-hour and weekly usage
          json     Print usage as JSON
          launch   Open the Token Bar menu bar app
          auth     Check whether local Codex usage data is available
          doctor   Check local Codex data availability
          help     Show this help
        """
    }

    private static func authStatus() -> Int32 {
        let codexDirectory = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex")

        guard FileManager.default.fileExists(atPath: codexDirectory.path) else {
            print("Codex is not set up on this Mac. Open Codex and sign in first.")
            return 1
        }

        do {
            let snapshot = try CodexUsageReader().readSnapshot()
            if snapshot.eventsRead > 0 {
                print("Codex usage data is available.")
                print("Last Codex event: \(formatDate(snapshot.lastEventDate))")
                return 0
            }

            print("Codex is present, but no token usage events were found yet.")
            print("Open Codex, run a prompt, then try again.")
            return 1
        } catch {
            print("Unable to read Codex usage data: \(error.localizedDescription)")
            return 1
        }
    }
}

private func formatPercent(_ value: Double) -> String {
    if value.rounded() == value {
        return "\(Int(value))%"
    }
    return "\(String(format: "%.1f", value))%"
}

private func formatTokens(_ tokens: Int) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    return formatter.string(from: NSNumber(value: tokens)) ?? "\(tokens)"
}

private func formatDate(_ date: Date?) -> String {
    guard let date else {
        return "unknown"
    }
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .short
    return formatter.string(from: date)
}

private func isoString(_ date: Date) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.string(from: date)
}

exit(TokenBarCLI.main(arguments: CommandLine.arguments))
