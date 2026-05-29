import Foundation
import Testing
@testable import TokenBarCore

@Test func parsesTokenCountEvent() throws {
    let line = """
    {"timestamp":"2026-05-29T03:53:28.966Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":56995,"cached_input_tokens":43648,"output_tokens":1133,"reasoning_output_tokens":291,"total_tokens":58128}},"rate_limits":{"limit_id":"codex","primary":{"used_percent":13.0,"window_minutes":300,"resets_at":1780042991},"secondary":{"used_percent":3.0,"window_minutes":10080,"resets_at":1780458660},"plan_type":"prolite"}}}
    """

    let event = try #require(parseTokenCountEvent(line: line))

    #expect(event.totalUsage.totalTokens == 58_128)
    #expect(event.rateLimits?.limitID == "codex")
    #expect(event.rateLimits?.planType == "prolite")
    #expect(event.rateLimits?.primary?.usedPercent == 13.0)
    #expect(event.rateLimits?.primary?.windowMinutes == 300)
    #expect(event.rateLimits?.secondary?.usedPercent == 3.0)
    #expect(event.rateLimits?.secondary?.windowMinutes == 10_080)
}

@Test func ignoresNonTokenCountEvents() {
    let line = #"{"timestamp":"2026-05-29T03:53:28.966Z","type":"event_msg","payload":{"type":"task_started"}}"#

    #expect(parseTokenCountEvent(line: line) == nil)
}

@Test func aggregatesDeltasAcrossWindows() throws {
    let root = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let sessions = root
        .appendingPathComponent("sessions", isDirectory: true)
        .appendingPathComponent("2026/05/29", isDirectory: true)

    try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)

    let file = sessions.appendingPathComponent("rollout.jsonl")
    let jsonl = """
    {"timestamp":"2026-05-29T00:00:00.000Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"total_tokens":100}},"rate_limits":{"primary":{"used_percent":10,"window_minutes":300},"secondary":{"used_percent":2,"window_minutes":10080},"plan_type":"pro"}}}
    {"timestamp":"2026-05-29T02:00:00.000Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"total_tokens":250}},"rate_limits":{"primary":{"used_percent":11,"window_minutes":300},"secondary":{"used_percent":3,"window_minutes":10080},"plan_type":"pro"}}}
    {"timestamp":"2026-05-29T03:00:00.000Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"total_tokens":250}},"rate_limits":{"primary":{"used_percent":11,"window_minutes":300},"secondary":{"used_percent":3,"window_minutes":10080},"plan_type":"pro"}}}
    {"timestamp":"2026-05-29T04:30:00.000Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"total_tokens":400}},"rate_limits":{"primary":{"used_percent":12,"window_minutes":300},"secondary":{"used_percent":4,"window_minutes":10080},"plan_type":"pro"}}}
    """
    try jsonl.write(to: file, atomically: true, encoding: .utf8)

    let now = parseTestDate("2026-05-29T05:00:00.000Z")
    let reader = CodexUsageReader(codexDirectory: root, now: { now })
    let snapshot = try reader.readSnapshot()

    #expect(snapshot.fiveHourTokens == 400)
    #expect(snapshot.weeklyTokens == 400)
    #expect(snapshot.latestRateLimits?.primary?.usedPercent == 12)
    #expect(snapshot.eventsRead == 4)
}

private func parseTestDate(_ string: String) -> Date {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.date(from: string)!
}
