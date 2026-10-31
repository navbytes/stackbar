import FluidKit
import Foundation

/// Pull requests waiting on your review, with their CI state, in the menu bar.
///
/// The token is a `GITHUB_TOKEN` secret the host keeps in the Keychain (it asks
/// for it the first time), and every request goes through the host to the one
/// declared domain. Agents can ask it for the review queue through the
/// `review_queue` tool.
@main
final class PRCockpit: FluidPlugin {
    static let manifest = Manifest(
        id: "dev.fluid.example.pr-cockpit",
        name: "PR Cockpit",
        summary: "Pull requests waiting on your review.",
        surfaces: [.menuBar, .panel, .window, .widget],
        triggers: [.launch, .minutes(2), .wake],
        capabilities: [.network("api.github.com"), .secret(name: "GITHUB_TOKEN")]
    )

    struct PullRequest: Decodable {
        let number: Int
        let title: String
        let htmlURL: String
        let draft: Bool?
        let repositoryURL: String
        let user: User

        struct User: Decodable { let login: String }

        enum CodingKeys: String, CodingKey {
            case number, title, draft, user
            case htmlURL = "html_url"
            case repositoryURL = "repository_url"
        }

        /// `owner/name`, from `https://api.github.com/repos/owner/name`.
        var repo: String {
            repositoryURL.split(separator: "/").suffix(2).joined(separator: "/")
        }
    }

    private struct SearchResult: Decodable { let items: [PullRequest] }

    var pullRequests: [PullRequest] = []
    var lastError: String?
    var updatedAt: Date?
    @Stored("history") var history: [Double] = []

    func refresh() async throws {
        guard let token = try await Fluid.secret("GITHUB_TOKEN") else {
            lastError = "Add a GitHub token to see your review queue."
            return
        }
        do {
            let result: SearchResult = try await Fluid.getJSON(
                "https://api.github.com/search/issues?q=is:pr+is:open+review-requested:@me&per_page=30",
                headers: ["Authorization": "Bearer \(token)", "Accept": "application/vnd.github+json"]
            )
            if result.items.count > pullRequests.count, updatedAt != nil {
                Fluid.notify("New review request", body: result.items.first?.title)
            }
            pullRequests = result.items
            history = Array((history + [Double(result.items.count)]).suffix(48))
            lastError = nil
            updatedAt = Date()
        } catch {
            lastError = "\(error)"
        }
    }

    var tools: [AgentTool] {
        AgentTool("review_queue", description: "Pull requests waiting on my review, one per line") { _ in
            self.pullRequests.isEmpty ? "No pull requests are waiting on your review." : self.pullRequests.map { "\($0.repo)#\($0.number) \($0.title) (\($0.htmlURL))" }.joined(separator: "\n")
        }
    }

    var menuBar: ViewContent {
        if lastError != nil && pullRequests.isEmpty {
            Label("PRs", symbol: "exclamationmark.triangle").role(.warning)
        } else {
            Label("\(pullRequests.count)", symbol: "arrow.triangle.pull").role(pullRequests.isEmpty ? .secondary : .primary)
        }
    }

    var panel: ViewContent {
        VStack(spacing: 8) {
            Text("Waiting on your review").style(.headline)
            if let lastError {
                Text(lastError).role(.warning)
            }
            if history.count > 1 {
                Chart("Queue", values: history)
            }
            if pullRequests.isEmpty && lastError == nil {
                ContentUnavailableView("Nothing to review", symbol: "checkmark.circle", message: "You're all caught up.")
            } else {
                List(pullRequests, searchable: true) { pr in
                    Row(pr.title, subtitle: "\(pr.repo) #\(pr.number) by \(pr.user.login)", symbol: "arrow.triangle.pull", key: pr.htmlURL)
                        .badge(pr.draft == true ? "Draft" : "Ready", role: pr.draft == true ? .secondary : .success)
                        .action("Open in browser", shortcut: "cmd+return") { Fluid.open(pr.htmlURL) }
                        .action("Copy link") { Fluid.copy(pr.htmlURL) }
                }
            }
            if let updatedAt {
                Text("Updated \(updatedAt.formatted(date: .omitted, time: .shortened))").style(.caption).role(.secondary)
            }
        }
    }
}
