import Foundation
import XCTest
@testable import StackbarKit

final class TemplateTests: XCTestCase {
    /// 2026-01-31 09:05 UTC, a Saturday, at a month's end.
    private let now = Date(timeIntervalSince1970: 1_769_850_300)
    private var environment: Template.Environment {
        Template.Environment(clipboard: "a b&c", selection: "Hello World", now: now, timeZone: TimeZone(identifier: "UTC")!, locale: Locale(identifier: "en_US_POSIX"), uuid: { "UUID-1" }, snippets: ["sig": "-- {argument name=\"who\" default=\"Nav\"}", "loop": "{snippet name=\"sig\"}"])
    }

    func testArgumentsBecomeTheCommandsArguments() throws {
        let template = try Template(#"https://github.com/{argument name="org" default="navbytes"}/{argument name="repo"}/issues?q={argument name="q"} {argument name="repo"}"#)
        XCTAssertEqual(template.arguments, [
            ArgumentSpec("org", required: false, defaultValue: "navbytes"),
            ArgumentSpec("repo"),
            ArgumentSpec("q"),
        ])
        let url = try template.render(["repo": "stackbar", "q": "is:open label:bug"], in: environment, encoding: .url).text
        XCTAssertEqual(url, "https://github.com/navbytes/stackbar/issues?q=is%3Aopen%20label%3Abug stackbar")
        XCTAssertEqual(try Template("{argument}").arguments, [ArgumentSpec("argument")])
    }

    func testRaycastManualSamples() throws {
        // From Raycast's quicklink and snippet documentation.
        XCTAssertEqual(try Template("https://www.google.com/search?q={argument}").render(["argument": "swift actors"], in: environment, encoding: .url).text, "https://www.google.com/search?q=swift%20actors")
        XCTAssertEqual(try Template("https://www.google.com/search?q={selection}").render(in: environment, encoding: .url).text, "https://www.google.com/search?q=Hello%20World")
        XCTAssertEqual(try Template(#"{date format="yyyy-MM-dd"}"#).render(in: environment).text, "2026-01-31")
        XCTAssertEqual(try Template(#"{date format="yyyy-MM-dd" offset="+1d"}"#).render(in: environment).text, "2026-02-01")
        XCTAssertEqual(try Template(#"{date format="yyyy-MM-dd" offset="+1M"}"#).render(in: environment).text, "2026-02-28", "a month after Jan 31 is Feb 28")
        XCTAssertEqual(try Template(#"{time format="HH:mm" offset="-2h -5m"}"#).render(in: environment).text, "07:00")
        XCTAssertEqual(try Template("{day}").render(in: environment).text, "Saturday")
        XCTAssertEqual(try Template(#"{day locale="fr-FR"}"#).render(in: environment).text, "samedi")
        XCTAssertEqual(try Template("{clipboard | uppercase}").render(in: environment).text, "A B&C")
        XCTAssertEqual(try Template("{uuid}").render(in: environment).text, "UUID-1")
    }

    func testOptionsAreAChoice() throws {
        let template = try Template(#"I'm {argument name="tone" options="happy, sad"} today"#)
        XCTAssertEqual(template.arguments.first?.options, ["happy", "sad"])
        XCTAssertEqual(try template.render(["tone": "sad"]).text, "I'm sad today")
        XCTAssertThrowsError(try template.render(["tone": "angry"])) { error in
            XCTAssertTrue("\(error)".contains("not one of happy, sad"), "\(error)")
        }
    }

    func testModifiersChainLeftToRight() throws {
        let environment = Template.Environment(clipboard: "  Mixed Case  ")
        XCTAssertEqual(try Template("[{clipboard | trim | lowercase}]").render(in: environment).text, "[mixed case]")
        XCTAssertEqual(try Template("{clipboard | trim | json-stringify}").render(in: environment).text, "\"Mixed Case\"")
        XCTAssertEqual(try Template("{clipboard | trim | percent-encode}").render(in: environment).text, "Mixed%20Case")
    }

    func testURLEncodingTouchesValuesNotTheTemplate() throws {
        let environment = self.environment
        XCTAssertEqual(try Template("https://x.com/a b?q={clipboard}").render(in: environment, encoding: .url).text, "https://x.com/a b?q=a%20b%26c")
        XCTAssertEqual(try Template("https://x.com/{clipboard | raw}").render(in: environment, encoding: .url).text, "https://x.com/a b&c")
        XCTAssertEqual(try Template("https://x.com/{clipboard | percent-encode}").render(in: environment, encoding: .url).text, "https://x.com/a%20b%26c", "not encoded twice")
        XCTAssertEqual(try Template("{clipboard}").render(in: environment).text, "a b&c", "no encoding outside links")
    }

    func testUnknownAndMalformedPlaceholdersStayAsWritten() throws {
        let source = #"function() { return 1 } {clipbaord} {date | shout} {argument name="x} \{literal\} {cursor"#
        let template = try Template(source)
        XCTAssertTrue(template.arguments.isEmpty)
        let text = try template.render(in: environment).text
        XCTAssertEqual(text, #"function() { return 1 } {clipbaord} {date | shout} {argument name="x} {literal} {cursor"#)
        XCTAssertEqual(template.unrecognized, ["{clipbaord}", "{date | shout}"], "an unclosed quote is not a group")
    }

    func testCursorAndSnippets() throws {
        let rendered = try Template("Dear {argument name=\"who\" default=\"team\"},\n\n{cursor}\n\n{snippet name=\"sig\"}").render(in: environment)
        XCTAssertEqual(rendered.text, "Dear team,\n\n\n\n-- Nav", "the snippet keeps its own default")
        XCTAssertEqual(rendered.cursorFromEnd, "\n\n-- Nav".count)
        XCTAssertNil(try Template("no cursor").render().cursorFromEnd)
        XCTAssertThrowsError(try Template("{snippet name=\"loop\"}").render(in: environment), "one level deep only")
        XCTAssertThrowsError(try Template("{snippet name=\"missing\"}").render(in: environment))
    }

    func testErrorsNameThePlaceholder() throws {
        XCTAssertThrowsError(try Template("{argument name=\"repo\"}").render()) { error in
            XCTAssertEqual("\(error)", "{argument name=\"repo\"}: needs a value for repo")
        }
        XCTAssertThrowsError(try Template("{date offset=\"tomorrow\"}").render(in: environment)) { error in
            XCTAssertTrue("\(error)".hasPrefix("{date offset=\"tomorrow\"}: offset"), "\(error)")
        }
        XCTAssertThrowsError(try Template("{clipboard offset=2}").render(in: environment))
        XCTAssertThrowsError(try Template("{argument name=a}{argument name=b}{argument name=c}{argument name=d}")) { error in
            XCTAssertTrue("\(error)".contains("at most 3"), "\(error)")
        }
        XCTAssertThrowsError(try Template(#"{argument name=a default=x}{argument name=a default=y}"#))
    }

    func testEmptyClipboardAndSelectionRenderEmpty() throws {
        XCTAssertEqual(try Template("[{clipboard}][{selection}]").render().text, "[][]")
    }
}
