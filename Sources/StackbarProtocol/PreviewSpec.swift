/// A plugin preview (a scene with sample data, for screenshots) as the
/// plugin's `--previews` prints it.
public struct PreviewSpec: Codable, Equatable, Sendable {
    public var name: String
    public var title: String
    /// The surface the scene is about (the panel unless it says otherwise).
    public var surface: Surface

    public init(name: String, title: String, surface: Surface = .panel) {
        self.name = name
        self.title = title
        self.surface = surface
    }
}

/// The environment variable that puts a plugin in preview mode. The host
/// never sets it; `stackbarctl render --preview` does.
public let stackbarPreviewEnvironmentKey = "STACKBAR_PREVIEW"
