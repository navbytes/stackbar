import Foundation

/// "Report a Problem": a new GitHub issue on the bug form with the version,
/// macOS and `stackbarctl doctor` filled in. Nothing is sent until the user
/// submits the issue in their browser.
public enum ProblemReport {
    /// The repository of this build (`Distribution.links.repository`).
    public static var repository: URL { Distribution.current.links.repository }

    /// GitHub prefills an issue form's fields from query items named by the
    /// fields' ids (`.github/ISSUE_TEMPLATE/bug.yml`).
    public static func issueURL(version: String, macOS: String, doctor: String) -> URL {
        var components = URLComponents(url: Distribution.current.issuesURL.appendingPathComponent("new"), resolvingAgainstBaseURL: false)!
        // Long URLs fail at GitHub; doctor output is a handful of lines.
        let doctor = String(doctor.trimmingCharacters(in: .whitespacesAndNewlines).prefix(4000))
        components.queryItems = [
            URLQueryItem(name: "template", value: "bug.yml"),
            URLQueryItem(name: "version", value: version),
            URLQueryItem(name: "macos", value: macOS),
            URLQueryItem(name: "doctor", value: doctor),
        ]
        return components.url!
    }

    /// Release notes, docs and the issue list, for the Help menu.
    public static var releasesURL: URL { Distribution.current.releasesURL }
    public static var issuesURL: URL { Distribution.current.issuesURL }
    /// The website, or the repository when the build has none.
    public static var docsURL: URL { Distribution.current.links.website ?? repository }
}
