import Foundation

public struct TokenUsage: Equatable {
    public var totalTokens: Int
    public var inputTokens: Int
    public var cachedInputTokens: Int
    public var outputTokens: Int
    public var reasoningOutputTokens: Int

    public init(
        totalTokens: Int,
        inputTokens: Int = 0,
        cachedInputTokens: Int = 0,
        outputTokens: Int = 0,
        reasoningOutputTokens: Int = 0
    ) {
        self.totalTokens = totalTokens
        self.inputTokens = inputTokens
        self.cachedInputTokens = cachedInputTokens
        self.outputTokens = outputTokens
        self.reasoningOutputTokens = reasoningOutputTokens
    }
}

public struct RateWindow: Equatable {
    public var usedPercent: Double
    public var windowMinutes: Int
    public var resetsAt: Date?

    public init(usedPercent: Double, windowMinutes: Int, resetsAt: Date?) {
        self.usedPercent = usedPercent
        self.windowMinutes = windowMinutes
        self.resetsAt = resetsAt
    }
}

public struct RateLimits: Equatable {
    public var limitID: String?
    public var planType: String?
    public var primary: RateWindow?
    public var secondary: RateWindow?

    public init(limitID: String?, planType: String?, primary: RateWindow?, secondary: RateWindow?) {
        self.limitID = limitID
        self.planType = planType
        self.primary = primary
        self.secondary = secondary
    }
}

public struct UsageSnapshot: Equatable {
    public var asOf: Date
    public var fiveHourTokens: Int
    public var weeklyTokens: Int
    public var latestTokenUsage: TokenUsage?
    public var latestRateLimits: RateLimits?
    public var lastEventDate: Date?
    public var filesScanned: Int
    public var eventsRead: Int

    public init(
        asOf: Date,
        fiveHourTokens: Int,
        weeklyTokens: Int,
        latestTokenUsage: TokenUsage?,
        latestRateLimits: RateLimits?,
        lastEventDate: Date?,
        filesScanned: Int,
        eventsRead: Int
    ) {
        self.asOf = asOf
        self.fiveHourTokens = fiveHourTokens
        self.weeklyTokens = weeklyTokens
        self.latestTokenUsage = latestTokenUsage
        self.latestRateLimits = latestRateLimits
        self.lastEventDate = lastEventDate
        self.filesScanned = filesScanned
        self.eventsRead = eventsRead
    }
}

public enum CodexUsageReaderError: Error, LocalizedError {
    case codexDirectoryMissing(URL)

    public var errorDescription: String? {
        switch self {
        case let .codexDirectoryMissing(url):
            return "Codex data directory was not found at \(url.path)."
        }
    }
}

public final class CodexUsageReader {
    private let fileManager: FileManager
    private let codexDirectory: URL
    private let now: () -> Date

    public init(
        codexDirectory: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex"),
        fileManager: FileManager = .default,
        now: @escaping () -> Date = Date.init
    ) {
        self.codexDirectory = codexDirectory
        self.fileManager = fileManager
        self.now = now
    }

    public func readSnapshot() throws -> UsageSnapshot {
        guard fileManager.fileExists(atPath: codexDirectory.path) else {
            throw CodexUsageReaderError.codexDirectoryMissing(codexDirectory)
        }

        let currentDate = now()
        let fiveHourStart = currentDate.addingTimeInterval(-5 * 60 * 60)
        let weekStart = currentDate.addingTimeInterval(-7 * 24 * 60 * 60)
        let files = jsonlFiles(modifiedSince: weekStart.addingTimeInterval(-24 * 60 * 60))

        var fiveHourTokens = 0
        var weeklyTokens = 0
        var latestTokenUsage: TokenUsage?
        var latestRateLimits: RateLimits?
        var lastEventDate: Date?
        var eventsRead = 0

        for file in files {
            var previousTotal: Int?

            for event in tokenCountEvents(in: file) {
                eventsRead += 1

                let currentTotal = event.totalUsage.totalTokens
                let delta: Int
                if let previousTotal {
                    delta = max(0, currentTotal - previousTotal)
                } else {
                    delta = currentTotal
                }
                previousTotal = currentTotal

                if event.timestamp >= fiveHourStart {
                    fiveHourTokens += delta
                }
                if event.timestamp >= weekStart {
                    weeklyTokens += delta
                }

                if lastEventDate == nil || event.timestamp > lastEventDate! {
                    lastEventDate = event.timestamp
                    latestTokenUsage = event.totalUsage
                    latestRateLimits = event.rateLimits
                }
            }
        }

        return UsageSnapshot(
            asOf: currentDate,
            fiveHourTokens: fiveHourTokens,
            weeklyTokens: weeklyTokens,
            latestTokenUsage: latestTokenUsage,
            latestRateLimits: latestRateLimits,
            lastEventDate: lastEventDate,
            filesScanned: files.count,
            eventsRead: eventsRead
        )
    }

    private func jsonlFiles(modifiedSince cutoff: Date) -> [URL] {
        let roots = [
            codexDirectory.appendingPathComponent("sessions", isDirectory: true),
            codexDirectory.appendingPathComponent("archived_sessions", isDirectory: true)
        ]

        var files: [URL] = []

        for root in roots where fileManager.fileExists(atPath: root.path) {
            guard let enumerator = fileManager.enumerator(
                at: root,
                includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
                options: [.skipsHiddenFiles]
            ) else {
                continue
            }

            for case let file as URL in enumerator where file.pathExtension == "jsonl" {
                guard let values = try? file.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey]),
                      values.isRegularFile == true,
                      (values.contentModificationDate ?? .distantPast) >= cutoff
                else {
                    continue
                }
                files.append(file)
            }
        }

        return files.sorted { lhs, rhs in
            let leftDate = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let rightDate = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return leftDate < rightDate
        }
    }

    private func tokenCountEvents(in file: URL) -> [TokenCountEvent] {
        guard let data = try? Data(contentsOf: file),
              let text = String(data: data, encoding: .utf8)
        else {
            return []
        }

        return text
            .split(separator: "\n")
            .compactMap { parseTokenCountEvent(line: String($0)) }
            .sorted { $0.timestamp < $1.timestamp }
    }
}

public func parseTokenCountEvent(line: String) -> TokenCountEvent? {
    guard line.contains("\"token_count\""),
          let data = line.data(using: .utf8),
          let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let timestampString = object["timestamp"] as? String,
          let timestamp = parseCodexDate(timestampString),
          let payload = object["payload"] as? [String: Any],
          payload["type"] as? String == "token_count",
          let info = payload["info"] as? [String: Any],
          let totalUsageObject = info["total_token_usage"] as? [String: Any],
          let totalUsage = TokenUsage(json: totalUsageObject)
    else {
        return nil
    }

    let rateLimits: RateLimits?
    if let rateLimitObject = payload["rate_limits"] as? [String: Any] {
        rateLimits = RateLimits(json: rateLimitObject)
    } else {
        rateLimits = nil
    }

    return TokenCountEvent(timestamp: timestamp, totalUsage: totalUsage, rateLimits: rateLimits)
}

public struct TokenCountEvent: Equatable {
    public var timestamp: Date
    public var totalUsage: TokenUsage
    public var rateLimits: RateLimits?

    public init(timestamp: Date, totalUsage: TokenUsage, rateLimits: RateLimits?) {
        self.timestamp = timestamp
        self.totalUsage = totalUsage
        self.rateLimits = rateLimits
    }
}

private extension TokenUsage {
    init?(json: [String: Any]) {
        guard let totalTokens = json.intValue(for: "total_tokens") else {
            return nil
        }

        self.init(
            totalTokens: totalTokens,
            inputTokens: json.intValue(for: "input_tokens") ?? 0,
            cachedInputTokens: json.intValue(for: "cached_input_tokens") ?? 0,
            outputTokens: json.intValue(for: "output_tokens") ?? 0,
            reasoningOutputTokens: json.intValue(for: "reasoning_output_tokens") ?? 0
        )
    }
}

private extension RateLimits {
    init(json: [String: Any]) {
        self.init(
            limitID: json["limit_id"] as? String,
            planType: json["plan_type"] as? String,
            primary: RateWindow(json: json["primary"] as? [String: Any]),
            secondary: RateWindow(json: json["secondary"] as? [String: Any])
        )
    }
}

private extension RateWindow {
    init?(json: [String: Any]?) {
        guard let json,
              let usedPercent = json.doubleValue(for: "used_percent"),
              let windowMinutes = json.intValue(for: "window_minutes")
        else {
            return nil
        }

        let resetsAt = json.doubleValue(for: "resets_at").map(Date.init(timeIntervalSince1970:))
        self.init(usedPercent: usedPercent, windowMinutes: windowMinutes, resetsAt: resetsAt)
    }
}

private extension Dictionary where Key == String, Value == Any {
    func intValue(for key: String) -> Int? {
        if let int = self[key] as? Int {
            return int
        }
        if let double = self[key] as? Double {
            return Int(double)
        }
        if let string = self[key] as? String {
            return Int(string)
        }
        return nil
    }

    func doubleValue(for key: String) -> Double? {
        if let double = self[key] as? Double {
            return double
        }
        if let int = self[key] as? Int {
            return Double(int)
        }
        if let string = self[key] as? String {
            return Double(string)
        }
        return nil
    }
}

private func parseCodexDate(_ string: String) -> Date? {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.date(from: string)
}
