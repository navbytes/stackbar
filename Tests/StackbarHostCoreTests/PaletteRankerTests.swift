import XCTest
@testable import StackbarHostCore
import StackbarProtocol

/// The palette's one ranker (openspec/changes/palette-ranking): tiers, learned
/// picks, Top Hit, and the cases earlier fixes pinned (#114, #116, #118).
final class PaletteRankerTests: XCTestCase {
    // MARK: Matcher

    func testTiers() {
        XCTAssertEqual(TextMatch.match("safari", in: "Safari")?.tier, .exact)
        XCTAssertEqual(TextMatch.match("prcockpit", in: "PR Cockpit")?.tier, .exact, "spaces don't matter")
        XCTAssertEqual(TextMatch.match("saf", in: "Safari")?.tier, .prefix)
        XCTAssertEqual(TextMatch.match("pr  cock", in: "PR Cockpit")?.tier, .prefix, "runs of spaces count as one")
        XCTAssertEqual(TextMatch.match("git", in: "Reset Git Cache")?.tier, .wordStart)
        XCTAssertEqual(TextMatch.match("cache", in: "reset-git-cache")?.tier, .wordStart)
        XCTAssertEqual(TextMatch.match("rgc", in: "Reset Git Cache")?.tier, .initials)
        XCTAssertEqual(TextMatch.match("vsc", in: "Visual Studio Code")?.tier, .initials)
        XCTAssertEqual(TextMatch.match("hub", in: "GitHub")?.tier, .substring)
        XCTAssertEqual(TextMatch.match("gthb", in: "GitHub")?.tier, .inOrder)
        XCTAssertNil(TextMatch.match("xyz", in: "GitHub"))
        XCTAssertNil(TextMatch.match("  ", in: "GitHub"))
    }

    func testShorterTextIsBetterWithinATier() throws {
        let short = try XCTUnwrap(TextMatch.match("saf", in: "Safari"))
        let long = try XCTUnwrap(TextMatch.match("saf", in: "Safe Mode Settings"))
        XCTAssertEqual(short.tier, long.tier)
        XCTAssertGreaterThan(short.quality, long.quality)
    }

    // MARK: Learning

    private final class Clock: @unchecked Sendable { var now = Date(timeIntervalSince1970: 1_800_000_000) }
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    private func picks() -> PalettePicks {
        let now = start
        return PalettePicks(file: nil) { now }
    }

    private func command(_ id: String, _ title: String, plugin: String = "p") -> PaletteIndex.Entry {
        PaletteIndex.Entry(pluginID: plugin, pluginName: "Plugin \(plugin)", title: title, kind: .command(CommandSpec(id: id, title: title)))
    }

    private func row(_ title: String, plugin: String = "io.apps", command: String = "search", key: String? = nil) -> PaletteIndex.Entry {
        var entry = PaletteIndex.Entry(pluginID: plugin, pluginName: "Applications", title: title, kind: .action(ActionID("a/\(title)"), value: nil))
        entry.rankKey = "\(plugin)|row|\(command)|\(key ?? title)"
        return entry
    }

    private func ranked(_ entries: [PaletteIndex.Entry], _ query: String, picks: PalettePicks? = nil, usage: PaletteUsage? = nil) -> [String] {
        let ranker = PaletteRanker(query: query, usage: usage, picks: picks)
        return entries.enumerated()
            .compactMap { offset, entry in ranker.score(entry).map { (entry.title, $0, offset) } }
            .sorted { ($0.1, -$0.2) > ($1.1, -$1.2) }
            .map(\.0)
    }

    func testAPickForTheSameTextMovesItUp() {
        let apps = [row("Safari"), row("Slack"), row("Spotify")]
        XCTAssertEqual(ranked(apps, "s").first, "Slack", "shortest first before any pick")
        let picks = picks()
        picks.record(query: "s", id: apps[0].learnID)
        XCTAssertEqual(ranked(apps, "s", picks: picks).first, "Safari")
        XCTAssertEqual(ranked(apps, "S ", picks: picks).first, "Safari", "the text is compared case- and space-blind")
    }

    func testTwoPicksLiftARowOneTier() {
        let entries = [command("review", "Code Review"), row("Visual Studio Code")]
        XCTAssertEqual(ranked(entries, "code").first, "Code Review", "a prefix beats a word start")
        let picks = picks()
        picks.record(query: "code", id: entries[1].learnID)
        XCTAssertEqual(ranked(entries, "code", picks: picks).first, "Code Review", "one pick isn't a habit yet")
        picks.record(query: "code", id: entries[1].learnID)
        XCTAssertEqual(ranked(entries, "code", picks: picks).first, "Visual Studio Code")
    }

    func testALongerTextTeachesTheShorterAtHalfWeight() {
        let picks = picks()
        picks.record(query: "slack", id: "slack")
        picks.record(query: "sl", id: "slack")
        XCTAssertEqual(picks.weights(for: "sl")["slack"] ?? 0, 1.5, accuracy: 0.001)
        XCTAssertEqual(picks.weights(for: "slack")["slack"] ?? 0, 1, accuracy: 0.001, "a shorter text doesn't teach a longer one")
        XCTAssertNil(picks.weights(for: "slx")["slack"])
    }

    func testLearningNeverAddsARow() {
        let apps = [row("Safari"), row("Slack")]
        let picks = picks()
        picks.record(query: "x", id: apps[1].learnID)
        picks.record(query: "x", id: apps[1].learnID)
        XCTAssertEqual(ranked(apps, "x", picks: picks), [])
    }

    func testPicksFade() {
        let clock = Clock()
        let fading = PalettePicks(file: nil) { clock.now }
        fading.record(query: "s", id: "slack")
        clock.now = start.addingTimeInterval(PaletteUsage.halfLife)
        XCTAssertEqual(fading.weights(for: "s")["slack"] ?? 0, 0.5, accuracy: 0.001)
    }

    func testForgetClearAndSave() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("picks-\(UUID().uuidString.prefix(8))")
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("palette-picks.json")
        let now = start
        let picks = PalettePicks(file: file) { now }
        picks.record(query: "s", id: "slack")
        picks.record(query: "sa", id: "safari")
        XCTAssertEqual(PalettePicks(file: file) { now }.weights(for: "s").keys.sorted(), ["safari", "slack"], "saved and read back")
        picks.forget("slack")
        XCTAssertEqual(PalettePicks(file: file) { now }.weights(for: "s").keys.sorted(), ["safari"])
        picks.clear()
        XCTAssertEqual(PalettePicks(file: file) { now }.weights(for: "s"), [:])

        let usage = PaletteUsage(file: nil) { now }
        usage.record("slack")
        usage.record("safari")
        usage.forget("slack")
        XCTAssertEqual(usage.score("slack"), 0)
        XCTAssertGreaterThan(usage.score("safari"), 0)
        usage.clear()
        XCTAssertEqual(usage.score("safari"), 0)
    }

    func testOnlyTheNewestPairsAreKept() {
        let clock = Clock()
        let picks = PalettePicks(file: nil) { clock.now }
        for index in 0...PalettePicks.limit {
            clock.now = start.addingTimeInterval(Double(index))
            picks.record(query: "q\(index)", id: "item")
        }
        XCTAssertNil(picks.weights(for: "q0")["item"], "the oldest pair went")
        XCTAssertNotNil(picks.weights(for: "q\(PalettePicks.limit)")["item"])
    }

    // MARK: Score

    func testAnAliasPrefixBeatsAnyNamePrefix() {
        var aliased = command("search", "Search Pull Requests")
        aliased.alias = "gh"
        let entries = [command("pull", "Git"), aliased]
        XCTAssertEqual(ranked(entries, "g").first, "Search Pull Requests")
        XCTAssertEqual(ranked(entries, "git").first, "Git", "an exact name beats an alias prefix")
        XCTAssertEqual(PaletteRanker(query: "gh").score(aliased).map { $0 >= PaletteRanker.exactAlias }, true)
    }

    func testARootRowIsNotFoundByItsPluginName() {
        let ranker = PaletteRanker(query: "applic")
        XCTAssertNil(ranker.score(row("Safari")), "every app row would match \"Applications\"")
        XCTAssertNotNil(ranker.score(PaletteIndex.Entry(pluginID: "a", pluginName: "Applications", title: "Refresh", kind: .action("a/r", value: nil))),
                        "a panel row is still found by its plugin's name")
    }

    func testATitleThatStartsWithTheTextBeatsASubtitleThatIsIt() {
        let entries = [PaletteIndex.Entry(pluginID: "c", pluginName: "Clock", title: "Refresh Clock", subtitle: "Refresh", kind: .action("r", value: nil)),
                       command("refresh", "Refresh Reviews")]
        XCTAssertEqual(ranked(entries, "refresh").first, "Refresh Reviews")
    }

    func testUseBreaksNearTiesOnly() {
        let now = start
        let usage = PaletteUsage(file: nil) { now }
        let entries = [command("a", "Notes Sync"), command("b", "Notes")]
        for _ in 0..<50 { usage.record(entries[0].learnID) }
        XCTAssertEqual(ranked(entries, "notes", usage: usage).first, "Notes", "heavy use doesn't beat an exact name")
        let close = [command("c", "Notes Sync"), command("d", "Notes Sort")]
        for _ in 0..<5 { usage.record(close[1].learnID) }
        XCTAssertEqual(ranked(close, "notes", usage: usage).first, "Notes Sort")
    }

    // MARK: Sections

    func testALearnedPluginRowBecomesTheTopHit() {
        let apps = PaletteSection(title: "Applications", entries: [row("Safari"), row("Slack")])
        let results = [command("s", "Snippets")]
        let picks = picks()
        picks.record(query: "s", id: row("Slack").learnID)
        picks.record(query: "s", id: row("Slack").learnID)
        let ranker = PaletteRanker(query: "s", picks: picks)
        let sections = PaletteSection.group(results, query: "s", plugins: [apps], ranker: ranker) { _ in false }
        XCTAssertEqual(sections.map(\.title), [PaletteSection.topHitTitle, "Applications", "Results"])
        XCTAssertEqual(sections.first?.entries.map(\.title), ["Slack"])
        XCTAssertEqual(sections[1].entries.map(\.title), ["Safari"], "the Top Hit leaves its section")
    }

    func testTheBestFirstRowLeadsItsSectionWithoutATopHit() {
        let apps = PaletteSection(title: "Applications", entries: [row("Safari"), row("Slack")])
        let sections = PaletteSection.group([command("safe", "Safe Mode")], query: "saf", plugins: [apps]) { _ in false }
        XCTAssertEqual(sections.map(\.title), ["Applications", "Results"])
    }

    func testAPatternSectionStillLeads() {
        let sum = PaletteSection(title: "Calculator", entries: [row("4", plugin: "calc", command: "sum")], leads: true)
        let apps = PaletteSection(title: "Applications", entries: [row("2Do")])
        let sections = PaletteSection.group([], query: "2+2", plugins: [apps, sum]) { _ in false }
        XCTAssertEqual(sections.first?.title, "Calculator")
    }

    func testRowsWithoutAMatchStayAfterTheResults() {
        let files = PaletteSection(title: "Files", entries: [row("Budget.numbers", plugin: "files")])
        let sections = PaletteSection.group([command("q", "Quarterly Report")], query: "quarterly", plugins: [files]) { _ in false }
        XCTAssertEqual(sections.map(\.title), ["Results", "Files"], "a file found by its contents comes after a name match")
    }
}
