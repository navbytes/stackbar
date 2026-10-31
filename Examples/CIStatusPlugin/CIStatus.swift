import StackbarKit
import Foundation

/// The latest GitHub Actions runs for the repositories you pick, red first.
@main
final class CIStatus: StackbarPlugin {
    static let manifest = Manifest(
        id: "io.navbytes.stackbar.example.ci-status",
        name: "CI Status",
        summary: "Latest GitHub Actions runs for your repositories.",
        surfaces: [.menuBar, .panel, .widget],
        triggers: [.launch, .minutes(3), .wake],
        capabilities: [.network("api.github.com"), .secret(name: "GITHUB_TOKEN")]
    )

    struct Run: Decodable {
        let name: String?
        let status: String
        let conclusion: String?
        let headBranch: String?
        let htmlURL: String
        let runNumber: Int

        enum CodingKeys: String, CodingKey {
            case name, status, conclusion
            case headBranch = "head_branch"
            case htmlURL = "html_url"
            case runNumber = "run_number"
        }

        var failed: Bool { conclusion == "failure" || conclusion == "timed_out" || conclusion == "startup_failure" }
        var running: Bool { status != "completed" }
    }

    private struct Runs: Decodable {
        let workflowRuns: [Run]
        enum CodingKeys: String, CodingKey { case workflowRuns = "workflow_runs" }
    }

    @Stored("repos") var repos: [String] = []
    var latest: [String: Run] = [:]
    var problem: String?

    private var failing: [String] { repos.filter { latest[$0]?.failed == true } }

    func refresh() async throws {
        guard !repos.isEmpty else { return }
        guard let token = try await Stackbar.secret("GITHUB_TOKEN") else {
            problem = "Add a GitHub token to see your runs."
            return
        }
        let before = Set(failing)
        problem = nil
        for repo in repos {
            do {
                let runs: Runs = try await Stackbar.getJSON(
                    "https://api.github.com/repos/\(repo)/actions/runs?per_page=1",
                    headers: ["Authorization": "Bearer \(token)", "Accept": "application/vnd.github+json"]
                )
                latest[repo] = runs.workflowRuns.first
            } catch {
                problem = "\(repo): \(error)"
            }
        }
        for repo in Set(failing).subtracting(before) {
            Stackbar.notify("CI failed: \(repo)", body: latest[repo]?.name)
        }
    }

    var menuBar: ViewContent {
        if repos.isEmpty {
            Label("", symbol: "checkmark.seal")
        } else if !failing.isEmpty {
            Label("\(failing.count)", symbol: "xmark.seal.fill").role(.critical)
        } else if repos.contains(where: { latest[$0]?.running == true }) {
            Label("", symbol: "clock.badge.checkmark").role(.accent)
        } else {
            Label("", symbol: "checkmark.seal.fill").role(.success)
        }
    }

    var panel: ViewContent {
        if let problem { Text(problem).role(.warning).style(.caption) }
        if repos.isEmpty {
            ContentUnavailableView("No repositories", symbol: "shippingbox", message: "Add one as owner/name.")
        } else {
            List(repos.sorted { (latest[$0]?.failed == true ? 0 : 1) < (latest[$1]?.failed == true ? 0 : 1) }) { repo in
                row(repo)
            }
        }
        TextField("Add owner/name", key: "repo") { repo in
            let repo = repo.trimmingCharacters(in: .whitespaces)
            guard repo.split(separator: "/").count == 2, !self.repos.contains(repo) else { return }
            self.repos.append(repo)
            try await self.refresh()
        }
    }

    var tools: [AgentTool] {
        AgentTool("ci_status", description: "Latest CI run per repository") { _ in
            self.repos.map { repo in
                guard let run = self.latest[repo] else { return "\(repo): unknown" }
                return "\(repo): \(run.name ?? "run") #\(run.runNumber) on \(run.headBranch ?? "?") is \(run.conclusion ?? run.status) (\(run.htmlURL))"
            }.joined(separator: "\n")
        }
    }

    private func row(_ repo: String) -> Row {
        guard let run = latest[repo] else {
            return Row(repo, subtitle: "No runs yet", symbol: "circle.dotted", key: repo)
                .action("Remove", role: .critical) { self.repos.removeAll { $0 == repo } }
        }
        let (badge, role): (String, Role) = run.running ? ("Running", .accent) : run.failed ? ("Failed", .critical) : (run.conclusion == "success" ? "Passed" : (run.conclusion ?? "Done").capitalized, run.conclusion == "success" ? .success : .secondary)
        return Row(repo, subtitle: "\(run.name ?? "Run") #\(run.runNumber) · \(run.headBranch ?? "")", symbol: "shippingbox", key: repo)
            .badge(badge, role: role)
            .action("Open run", shortcut: "cmd+return") { Stackbar.open(run.htmlURL) }
            .action("Remove", role: .critical) { self.repos.removeAll { $0 == repo } }
    }
}
