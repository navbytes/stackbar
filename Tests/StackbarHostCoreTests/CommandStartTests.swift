import StackbarHostCore
import StackbarProtocol
import XCTest

final class CommandStartTests: XCTestCase {
    private func entry(_ kind: CommandSpec.Kind = .run, _ arguments: [ArgumentSpec] = [], exposure: CommandSpec.Exposure = .everywhere) -> CommandRegistry.Entry {
        CommandRegistry.Entry(pluginID: "dev.t", pluginName: "T", spec: CommandSpec(id: "c", title: "Do It", kind: kind, arguments: arguments, exposure: exposure))
    }

    private let query = ArgumentSpec("query", placeholder: "Search for")
    private let optional = ArgumentSpec("tone", required: false)
    private let choice = ArgumentSpec("unit", options: ["km", "mi"])

    func testACommandWithoutArgumentsRunsFromEverywhere() {
        let sources: [InvocationSource] = [.palette, .hotkey, .link, .spotlight, .shortcuts, .panel]
        for source in sources {
            XCTAssertEqual(CommandStart.plan(entry(), source: source), .run(arguments: [:]), "\(source)")
        }
    }

    func testRequiredArgumentsAskUntilTheyAreFilled() {
        for source in [InvocationSource.palette, .hotkey, .link, .panel] {
            XCTAssertEqual(CommandStart.plan(entry(.run, [query]), source: source), .ask(arguments: ["query": ""]), "\(source)")
            XCTAssertEqual(CommandStart.plan(entry(.run, [query]), source: source, arguments: ["query": "cats"]), .run(arguments: ["query": "cats"]), "\(source)")
        }
    }

    /// Picked in the palette, a command shows its optional fields first;
    /// a hotkey, link or button runs it with the defaults.
    func testOptionalArgumentsAskOnlyWhenPickedInThePalette() {
        XCTAssertEqual(CommandStart.plan(entry(.run, [optional, choice]), source: .palette), .ask(arguments: ["tone": "", "unit": "km"]))
        for source in [InvocationSource.hotkey, .link, .spotlight, .panel] {
            XCTAssertEqual(CommandStart.plan(entry(.run, [optional, choice]), source: source), .run(arguments: ["tone": "", "unit": "km"]), "\(source)")
        }
        XCTAssertEqual(CommandStart.plan(entry(.run, [optional]), source: .palette, input: "warm"), .run(arguments: ["tone": "warm"]))
    }

    /// Typed text fills a run command's first argument and a view's search,
    /// from an alias, a fallback or Spotlight alike.
    func testInputFillsTheFirstArgumentOrTheViewsSearch() {
        for source in [InvocationSource.palette, .spotlight] {
            XCTAssertEqual(CommandStart.plan(entry(.run, [query]), source: source, input: " cats "), .run(arguments: ["query": "cats"]))
            XCTAssertEqual(CommandStart.plan(entry(.view, [choice]), source: source, input: "cats"), .openView(CommandQuery(text: "cats", arguments: ["unit": "km"])))
            XCTAssertEqual(CommandStart.plan(entry(.view), source: source, input: "cats"), .openView(CommandQuery(text: "cats")))
        }
        XCTAssertEqual(CommandStart.plan(entry(.run, [query]), source: .link, arguments: ["query": "dogs"], input: "cats"), .run(arguments: ["query": "dogs"]),
                       "a value the caller already has wins over typed text")
    }

    func testViewsOpenWithTheirDefaults() {
        XCTAssertEqual(CommandStart.plan(entry(.view, [query, choice]), source: .hotkey, arguments: ["unit": "mi"]),
                       .openView(CommandQuery(arguments: ["query": "", "unit": "mi"])))
    }

    func testOutsideSourcesCantStartAStackbarOnlyCommand() {
        let inside = entry(exposure: .stackbarOnly)
        for source in [InvocationSource.link, .spotlight, .shortcuts] {
            XCTAssertEqual(CommandStart.plan(inside, source: source), .refuse("Do It can only be run from inside Stackbar"), "\(source)")
        }
        for source in [InvocationSource.palette, .hotkey, .panel] {
            XCTAssertEqual(CommandStart.plan(inside, source: source), .run(arguments: [:]), "\(source)")
        }
    }

    func testASwitchedOffCommandOnlyStartsFromInsideThePalette() {
        let off = CommandPreference(enabled: false)
        for source in [InvocationSource.hotkey, .link, .spotlight, .shortcuts] {
            XCTAssertEqual(CommandStart.plan(entry(), preference: off, source: source), .refuse("Do It is switched off in Stackbar's settings"), "\(source)")
        }
        XCTAssertEqual(CommandStart.plan(entry(), preference: off, source: .panel), .run(arguments: [:]), "a plugin's own button still works")
    }

    func testMissingNamesTheFirstEmptyRequiredArgument() {
        let spec = entry(.run, [optional, query]).spec
        XCTAssertEqual(CommandStart.missing(spec, ["tone": "x"])?.name, "query")
        XCTAssertNil(CommandStart.missing(spec, ["query": "x"]))
    }
}
