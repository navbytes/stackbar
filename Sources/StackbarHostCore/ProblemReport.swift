import Foundation

/// "Report a Problem": a new GitHub issue on the bug form with the version,
/// macOS and `stackbarctl doctor` filled in. Nothing is sent until the user
/// submits the issue in their browser.
public enum ProblemReport {
    public static let repository = "navbytes/stackbar"

    /// GitHub prefills an issue form's fields from query items named by the
    /// fields' ids (`.github/ISSUE_TEMPLATE/bug.yml`).
    public static func issueURL(version: String, macOS: String, doctor: String) -> URL {
        var components = URLComponents(string: "https://github.com/\(repository)/issues/new")!
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
    public static let releasesURL = URL(string: "https://github.com/\(repository)/releases")!
    public static let issuesURL = URL(string: "https://github.com/\(repository)/issues")!
    public static let docsURL = URL(string: "https://stackbar.app")!
}
