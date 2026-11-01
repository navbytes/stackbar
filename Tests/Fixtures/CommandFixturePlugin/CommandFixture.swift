import StackbarKit
import Foundation

/// A test plugin whose commands each do the least that reaches one host
/// feature: the file panels, opening with a chosen app, pasting with the
/// clipboard restored and the caret placed, a form that validates, a view of
/// rows with actions, and a storage grant above the default 1 MB. Its links
/// become commands of their own, as Quicklinks' do.
@main
final class CommandFixture: StackbarPlugin {
    static let manifest = Manifest(
        id: "io.navbytes.stackbar.test.commands",
        name: "Command Fixture",
        surfaces: [.panel],
        triggers: [.launch],
        capabilities: [.openURLs(schemes: ["*"]), .clipboard, .storage(megabytes: 4)]
    )

    struct Link: Codable {
        var name: String
        var url: String
        var app: String?
    }

    @Stored("links") var links: [Link] = []
    var nameError: String?
    var urlError: String?

    var panel: ViewContent {
        Text("\(links.count) links")
    }

    var commands: [Command] {
        for (index, link) in links.enumerated() {
            Command("link-\(index)", title: link.name) { _ in .open(url: link.url, app: link.app) }
        }
        Command("import", title: "Import Links") { _ in
            guard let file = try await Stackbar.chooseFile(types: ["json"]) else { return .message("Import cancelled") }
            for var link in try JSONDecoder().decode([Link].self, from: file.data) {
                if let app = link.app { link.app = try await Stackbar.resolveApplication(app) }
                self.links.append(link)
            }
            return .message("Imported \(file.name)")
        }
        Command("export", title: "Export Links") { _ in
            .message(try await Stackbar.saveFile("links.json", data: JSONEncoder().encode(self.links)) ?? "Export cancelled")
        }
        Command("greet", title: "Paste Greeting") { invocation in
            .paste("Hello \(invocation["name"] ?? "you")!", cursorFromEnd: 1)
        }
        .argument("name", required: false)
        Command("create", title: "Create Link").view { _ in
            Form(submit: "Create", key: "new") {
                FormField.text("Name", name: "name", error: self.nameError)
                FormField.text("URL", name: "url", error: self.urlError)
            } onSubmit: { values in
                let name = values.string("name") ?? ""
                let url = values.string("url") ?? ""
                self.nameError = name.isEmpty ? "Give it a name" : nil
                self.urlError = url.contains("://") ? nil : "Needs a scheme"
                if self.nameError == nil, self.urlError == nil { self.links.append(Link(name: name, url: url)) }
            }
        }
        Command("search", title: "Search Links").view { invocation in
            List(searchable: true) {
                for (index, link) in self.links.enumerated() where invocation.text.isEmpty || link.name.localizedCaseInsensitiveContains(invocation.text) {
                    Row(link.name, subtitle: link.url, key: "\(index)")
                        .navigate("Open", to: "link-\(index)")
                        .action("Copy Link") { Stackbar.copy(link.url) }
                }
            }
        }
    }
}
