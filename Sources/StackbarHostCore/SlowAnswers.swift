import Foundation

/// Times a plugin's answers to the palette's view queries, so a search that
/// keeps the user waiting shows up in the log with its command and how long
/// it took. A view command's `search` that awaits a slow read before drawing
/// anything looks to the user like a stuck palette; this is what names it.
struct SlowAnswers: Sendable {
    /// An answer this long is logged.
    static let threshold: Double = 1

    private struct Asked: Sendable {
        var command: String
        var seq: Int
        var at: Date
    }

    /// The oldest unanswered query of each open view, by session. A newer
    /// query in the same view leaves it in place: the user has been waiting
    /// since the first one, and the next answer covers both.
    private var asked: [Int: Asked] = [:]
    /// Each open view's command, for queries that don't name it.
    private var commands: [Int: String] = [:]

    mutating func opened(session: Int, command: String, seq: Int, at now: Date = Date()) {
        commands[session] = command
        asked[session] = Asked(command: command, seq: seq, at: now)
    }

    mutating func updated(session: Int, seq: Int, at now: Date = Date()) {
        guard asked[session] == nil, let command = commands[session] else { return }
        asked[session] = Asked(command: command, seq: seq, at: now)
    }

    mutating func closed(session: Int) {
        asked[session] = nil
        commands[session] = nil
    }

    /// A tree arrived. Returns the line to log when it answered a query that
    /// waited `threshold` seconds or more.
    mutating func answered(session: Int, seq: Int, at now: Date = Date()) -> String? {
        guard let waiting = asked[session], seq >= waiting.seq else { return nil }
        asked[session] = nil
        let elapsed = now.timeIntervalSince(waiting.at)
        guard elapsed >= Self.threshold else { return nil }
        return "slow: \(waiting.command) took \(String(format: "%.2f", elapsed))s to answer the palette"
    }

    /// The process went away: nothing it was asked will be answered.
    mutating func reset() {
        asked = [:]
        commands = [:]
    }
}
