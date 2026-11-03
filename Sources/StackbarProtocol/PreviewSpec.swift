/// A plugin preview (a scene with sample data, for screenshots) as the
/// plugin's `--previews` prints it.
public struct PreviewSpec: Codable, Equatable, Sendable {
    public var name: String
    public var title: String

    public init(name: String, title: String) {
        self.name = name
        self.title = title
    }
}

/// The environment variable that puts a plugin in preview mode. The host
/// never sets it; `stackbarctl render --preview` does.
public let stackbarPreviewEnvironmentKey = "STACKBAR_PREVIEW"
