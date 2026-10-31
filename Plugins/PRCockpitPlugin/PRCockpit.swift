import FluidKit
import Foundation

/// Your pull requests and the ones waiting on your review, with CI and review
/// state, in the menu bar.
///
/// One GraphQL request a refresh fetches both lists with their checks, review
/// decision and merge conflicts. It tells you when someone asks for your
/// review, and when one of your own PRs is approved, gets changes requested,
/// or its checks fail. The token is a `GITHUB_TOKEN` secret the host keeps in
/// the Keychain (a fine-grained token with read access to pull requests is
/// enough), and every request goes through the host to the one declared
/// domain.
@main
final class PRCockpit: FluidPlugin {
    static let manifest = Manifest(
        id: "dev.fluid.pr-cockpit",
        name: "PR Cockpit",
        version: "1.0.0",
        summary: "Your pull requests and the ones waiting on your review, with CI and review state.",
        surfaces: [.menuBar, .panel, .window, .widget],
        triggers: [.launch, .minutes(2), .wake],
        capabilities: [.network("api.github.com"), .secret(name: "GITHUB_TOKEN")]
    )

    struct PullRequest: Decodable, Equatable {
        let number: Int
        let title: String
        let url: String
        let isDraft: Bool
        let updatedAt: Date
        let repository: Repository
        let author: Author?
        let reviewDecision: String?
        let mergeable: String?
        let headRefName: String?
        let additions: Int?
        let deletions: Int?
        let commits: Commits?
        let comments: Count?

        struct Count: Decodable, Equatable { let totalCount: Int }

        struct Repository: Decodable, Equatable { let nameWithOwner: String }
        struct Author: Decodable, Equatable { let login: String }
        struct Commits: Decodable, Equatable {
            struct Node: Decodable, Equatable {
                struct Commit: Decodable, Equatable {
                    struct Rollup: Decodable, Equatable { let state: String }
                    let statusCheckRollup: Rollup?
                }
                let commit: Commit
            }
            let nodes: [Node]
        }

        var repo: String { repository.nameWithOwner }
        var id: String { "\(repo)#\(number)" }

        /// SUCCESS, FAILURE, ERROR, PENDING, EXPECTED, or nil without checks.
        var checks: String? { commits?.nodes.last?.commit.statusCheckRollup?.state }
        var checksFailed: Bool { checks == "FAILURE" || checks == "ERROR" }
        /// Approved (or needing no review), checks green, no conflicts.
        var readyToMerge: Bool {
            !isDraft && (reviewDecision == "APPROVED" || reviewDecision == nil) && checks == "SUCCESS" && mergeable == "MERGEABLE"
        }
    }

    enum Tab: String, CaseIterable {
        case review = "To review"
        case mine = "Mine"
    }

    private struct Reply: Decodable {
        struct Data: Decodable {
            /// Search results, skipping any node that isn't a pull request.
            struct Search: Decodable {
                let nodes: [PullRequest]
                private enum Keys: String, CodingKey { case nodes }
                private struct Skip: Decodable {}

                init(from decoder: Decoder) throws {
                    var list = try decoder.container(keyedBy: Keys.self).nestedUnkeyedContainer(forKey: .nodes)
                    var found: [PullRequest] = []
                    while !list.isAtEnd {
                        if try list.decodeNil() { continue }
                        if let pr = try? list.decode(PullRequest.self) { found.append(pr) } else { _ = try list.decode(Skip.self) }
                    }
                    nodes = found
                }
            }
            let review: Search
            let mine: Search
        }
        struct Problem: Decodable { let message: String }
        let data: Data?
        let errors: [Problem]?
    }

    static let fragment = """
    fragment pr on PullRequest { number title url isDraft updatedAt repository { nameWithOwner } author { login } \
    reviewDecision mergeable headRefName additions deletions comments { totalCount } commits(last: 1) { nodes { commit { statusCheckRollup { state } } } } }
    """

    var toReview: [PullRequest] = []
    var mine: [PullRequest] = []
    var lastError: String?
    var updatedAt: Date?
    @Stored("tab") var tab = Tab.review.rawValue
    @Stored("includeTeams") var includeTeams = true
    @Stored("includeDrafts") var includeDrafts = false
    @Stored("notify") var notifyChanges = true
    @Stored("history") var history: [Double] = []
    /// When you last looked at each pull request (by URL), to mark new activity.
    @Stored("seen") var seen: [String: Date] = [:]
    @Stored("seenStarted") var seenStarted = false
    /// Hidden until they change: URL to the update time they were snoozed at.
    @Stored("snoozed") var snoozed: [String: Date] = [:]
    @Stored("hiddenRepos") var hiddenRepos: [String] = []

    func refresh() async throws {
        guard let token = try await Fluid.secret("GITHUB_TOKEN") else {
            lastError = "Add a GitHub token to see your pull requests."
            return
        }
        let requested = includeTeams ? "review-requested:@me" : "user-review-requested:@me"
        let draft = includeDrafts ? "" : " draft:false"
        let query = """
        query { \
        review: search(query: "is:pr is:open archived:false \(requested)\(draft)", type: ISSUE, first: 40) { nodes { ...pr } } \
        mine: search(query: "is:pr is:open archived:false author:@me", type: ISSUE, first: 40) { nodes { ...pr } } \
        } \(Self.fragment)
        """
        do {
            let body = try JSONEncoder().encode(["query": query])
            let response = try await Fluid.http(HTTPRequest(url: "https://api.github.com/graphql", method: "POST", headers: [
                "Authorization": "Bearer \(token)", "Content-Type": "application/json", "Accept": "application/json",
            ], body: body))
            guard (200..<300).contains(response.status) else {
                throw HostError(response.status == 401 ? "GitHub rejected the token (401); set a new GITHUB_TOKEN" : "GitHub answered \(response.status): \(String(decoding: response.body.prefix(200), as: UTF8.self))")
            }
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let reply = try decoder.decode(Reply.self, from: response.body)
            guard let data = reply.data else { throw HostError(reply.errors?.map(\.message).joined(separator: "; ") ?? "GitHub sent no data") }
            update(review: data.review.nodes, mine: data.mine.nodes)
            lastError = nil
        } catch {
            lastError = "\(error)"
        }
    }

    /// Takes the new lists, telling the user what changed since last time.
    func update(review: [PullRequest], mine newMine: [PullRequest]) {
        if notifyChanges, updatedAt != nil {
            let known = Set(toReview.map(\.id))
            let added = review.filter { !known.contains($0.id) }
            if added.count == 1, let pr = added.first {
                Fluid.notify("Review requested: \(pr.title)", body: "\(pr.id) by \(pr.author?.login ?? "someone")")
            } else if added.count > 1 {
                Fluid.notify("\(added.count) new review requests", body: added.map(\.title).prefix(3).joined(separator: "\n"))
            }
            let before = Dictionary(mine.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            for pr in newMine {
                guard let old = before[pr.id] else { continue }
                if pr.reviewDecision != old.reviewDecision, pr.reviewDecision == "APPROVED" {
                    Fluid.notify("Approved: \(pr.title)", body: pr.id)
                } else if pr.reviewDecision != old.reviewDecision, pr.reviewDecision == "CHANGES_REQUESTED" {
                    Fluid.notify("Changes requested: \(pr.title)", body: pr.id)
                }
                if pr.checksFailed, !old.checksFailed {
                    Fluid.notify("Checks failed: \(pr.title)", body: pr.id)
                } else if pr.readyToMerge, !old.readyToMerge {
                    Fluid.notify("Ready to merge: \(pr.title)", body: pr.id)
                }
            }
        }
        toReview = review.sorted { $0.updatedAt > $1.updatedAt }
        mine = newMine.sorted { $0.updatedAt > $1.updatedAt }
        let current = Set((toReview + mine).map(\.url))
        if !seenStarted {
            seenStarted = true
            // First run: what is already there isn't news.
            seen = Dictionary((toReview + mine).map { ($0.url, $0.updatedAt) }, uniquingKeysWith: { first, _ in first })
        } else {
            seen = seen.filter { current.contains($0.key) }
        }
        snoozed = snoozed.filter { current.contains($0.key) }
        history = Array((history + [Double(review.count)]).suffix(48))
        updatedAt = Date()
    }

    // MARK: Filtering and attention

    func isShown(_ pr: PullRequest) -> Bool {
        if hiddenRepos.contains(pr.repo) { return false }
        if let at = snoozed[pr.url], pr.updatedAt <= at { return false }
        return true
    }

    var shownReview: [PullRequest] { toReview.filter(isShown) }
    var shownMine: [PullRequest] { mine.filter(isShown) }
    var hiddenCount: Int { toReview.count + mine.count - shownReview.count - shownMine.count }

    func isNew(_ pr: PullRequest) -> Bool {
        guard let at = seen[pr.url] else { return true }
        return pr.updatedAt > at
    }

    func markSeen(_ pr: PullRequest) { seen[pr.url] = pr.updatedAt }

    func open(_ pr: PullRequest, path: String = "") {
        markSeen(pr)
        Fluid.open(pr.url + path)
    }

    // MARK: Words

    static func ago(_ date: Date, now: Date = Date()) -> String {
        let seconds = now.timeIntervalSince(date)
        if seconds < 3600 { return "\(max(1, Int(seconds / 60)))m" }
        if seconds < 86400 { return "\(Int(seconds / 3600))h" }
        return "\(Int(seconds / 86400))d"
    }

    func row(_ pr: PullRequest, showAuthor: Bool) -> Row {
        let size = pr.additions.map { "+\($0) −\(pr.deletions ?? 0)" }
        let comments = (pr.comments?.totalCount ?? 0) > 0 ? "\(pr.comments?.totalCount ?? 0) comments" : nil
        let subtitle = [pr.id, showAuthor ? pr.author.map { "by \($0.login)" } : nil, size, comments, Self.ago(pr.updatedAt)].compactMap { $0 }.joined(separator: " · ")
        var row = Row(pr.title, subtitle: subtitle, symbol: isNew(pr) ? "circle.fill" : pr.isDraft ? "pencil.circle" : "arrow.triangle.pull", key: pr.url)
        if isNew(pr) { row = row.badge("New", role: .accent) }
        if !showAuthor, pr.readyToMerge { row = row.badge("Ready to merge", role: .success) }
        switch pr.checks {
        case "SUCCESS": row = row.badge("Checks pass", role: .success)
        case "FAILURE", "ERROR": row = row.badge("Checks fail", role: .critical)
        case "PENDING", "EXPECTED": row = row.badge("Checks running", role: .warning)
        default: break
        }
        switch pr.reviewDecision {
        case "APPROVED": row = row.badge("Approved", role: .success)
        case "CHANGES_REQUESTED": row = row.badge("Changes requested", role: .critical)
        case "REVIEW_REQUIRED": if !showAuthor { row = row.badge("Needs review", role: .secondary) }
        default: break
        }
        if pr.mergeable == "CONFLICTING" { row = row.badge("Conflicts", role: .warning) }
        if pr.isDraft { row = row.badge("Draft") }
        row = row.action("Open in browser", shortcut: "cmd+return") { self.open(pr) }
            .action("Open files changed") { self.open(pr, path: "/files") }
            .action(isNew(pr) ? "Mark as seen" : "Mark as new", shortcut: "cmd+u") {
                if self.isNew(pr) { self.markSeen(pr) } else { self.seen[pr.url] = .distantPast }
            }
            .action("Snooze until it changes", shortcut: "cmd+s") { self.snoozed[pr.url] = pr.updatedAt }
            .action("Hide \(pr.repo)") { if !self.hiddenRepos.contains(pr.repo) { self.hiddenRepos.append(pr.repo) } }
            .action("Copy link") { Fluid.copy(pr.url) }
        if let branch = pr.headRefName {
            row = row.action("Copy branch name") { Fluid.copy(branch) }
        }
        return row.action("Copy as Markdown") { Fluid.copy("[\(pr.title) (\(pr.id))](\(pr.url))") }
    }

    var failingMine: Int { shownMine.filter(\.checksFailed).count }

    // MARK: Surfaces

    var menuBar: ViewContent {
        if lastError != nil && toReview.isEmpty && mine.isEmpty {
            Label("PRs", symbol: "exclamationmark.triangle").role(.warning)
        } else if failingMine > 0 {
            Label("\(shownReview.count) · \(failingMine) failing", symbol: "arrow.triangle.pull").role(.critical)
        } else {
            Label("\(shownReview.count)", symbol: "arrow.triangle.pull").role(shownReview.isEmpty ? .secondary : shownReview.contains(where: isNew) ? .accent : .primary)
        }
    }

    var panel: ViewContent {
        VStack(spacing: 8) {
            Picker("Show", options: [Tab.review, Tab.mine].map { "\($0.rawValue) (\($0 == .review ? shownReview.count : shownMine.count))" }, selection: selectedLabel) { label in
                self.tab = label.hasPrefix(Tab.mine.rawValue) ? Tab.mine.rawValue : Tab.review.rawValue
            }
            if let lastError {
                Text(lastError).role(.warning)
            }
            if tab == Tab.mine.rawValue {
                list(shownMine, showAuthor: false, empty: ("No open pull requests", "You have nothing open right now."))
            } else {
                if history.count > 1 { Chart("Review queue", values: history) }
                list(shownReview, showAuthor: true, empty: ("Nothing to review", "You're all caught up."))
            }
            HStack {
                if (shownReview + shownMine).contains(where: isNew) {
                    Button("Mark all as seen", symbol: "checkmark.circle") { (self.toReview + self.mine).forEach(self.markSeen) }
                }
                if hiddenCount > 0 || !hiddenRepos.isEmpty {
                    Button("Show \(hiddenCount) hidden", symbol: "eye", key: "unhide") {
                        self.snoozed = [:]
                        self.hiddenRepos = []
                    }
                }
            }
            if let updatedAt {
                Text("Updated \(updatedAt.formatted(date: .omitted, time: .shortened))").style(.caption).role(.secondary)
            }
            Section("Settings") {
                Toggle("Include requests to my teams", isOn: includeTeams) { on in
                    self.includeTeams = on
                    try await self.refresh()
                }
                Toggle("Include drafts to review", isOn: includeDrafts) { on in
                    self.includeDrafts = on
                    try await self.refresh()
                }
                Toggle("Notify me about changes", isOn: notifyChanges) { self.notifyChanges = $0 }
            }
        }
    }

    /// Both lists side by side in sections, since a window has the room.
    var window: ViewContent {
        if let lastError { Text(lastError).role(.warning) }
        List(searchable: true) {
            Section("Waiting on your review (\(shownReview.count))") {
                ForEach(shownReview) { pr in row(pr, showAuthor: true) }
            }
            Section("Yours (\(shownMine.count))") {
                ForEach(shownMine) { pr in row(pr, showAuthor: false) }
            }
        }
        if !hiddenRepos.isEmpty {
            Section("Hidden repositories") {
                ForEach(hiddenRepos) { repo in
                    Row(repo, symbol: "eye.slash", key: "hidden-\(repo)").action("Show again") { self.hiddenRepos.removeAll { $0 == repo } }
                }
            }
        }
    }

    var widget: ViewContent {
        LabeledContent("To review", value: "\(shownReview.count)")
        LabeledContent("Mine open", value: "\(shownMine.count)")
        if failingMine > 0 { LabeledContent("Failing checks", value: "\(failingMine)").role(.critical) }
        ForEach(shownReview.prefix(3)) { pr in Text(pr.title).style(.caption) }
    }

    var selectedLabel: String {
        let current = tab == Tab.mine.rawValue ? Tab.mine : Tab.review
        return "\(current.rawValue) (\(current == .review ? shownReview.count : shownMine.count))"
    }

    @ViewBuilder func list(_ prs: [PullRequest], showAuthor: Bool, empty: (String, String)) -> ViewContent {
        if prs.isEmpty {
            if lastError == nil { ContentUnavailableView(empty.0, symbol: "checkmark.circle", message: empty.1) }
        } else {
            List(prs, searchable: true) { pr in row(pr, showAuthor: showAuthor) }
        }
    }

    // MARK: Agents

    var tools: [AgentTool] {
        AgentTool("review_queue", description: "Pull requests waiting on my review, one per line") { _ in
            self.toReview.isEmpty ? "No pull requests are waiting on your review." : self.toReview.map { "\($0.id) \($0.title) by \($0.author?.login ?? "?") (\($0.url))" }.joined(separator: "\n")
        }
        AgentTool("my_pull_requests", description: "My open pull requests with their checks and review state, one per line") { _ in
            self.mine.isEmpty ? "You have no open pull requests." : self.mine.map { pr in
                "\(pr.id) \(pr.title): checks \(pr.checks?.lowercased() ?? "none"), review \(pr.reviewDecision?.lowercased().replacingOccurrences(of: "_", with: " ") ?? "none")\(pr.mergeable == "CONFLICTING" ? ", has conflicts" : "") (\(pr.url))"
            }.joined(separator: "\n")
        }
    }
}
