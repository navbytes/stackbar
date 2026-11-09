import Foundation

/// Display ids that survive a reconnect. A display's id is its vendor,
/// model and serial number. Two identical monitors without serial numbers
/// share one, so the second gets `#2`, and so on, counted left to right
/// (then top to bottom) by where they are arranged, not by the order macOS
/// lists them, which can swap from one reconnect to the next.
public enum DisplayIDs {
    public struct Screen: Equatable, Sendable {
        public var base: String
        public var x: Double
        public var y: Double

        public init(base: String, x: Double, y: Double) {
            self.base = base
            self.x = x
            self.y = y
        }
    }

    /// Each screen's id, in the order given.
    public static func ids(_ screens: [Screen]) -> [String] {
        var ids = screens.map(\.base)
        let groups = Dictionary(grouping: screens.indices, by: { screens[$0].base })
        for (_, members) in groups where members.count > 1 {
            let ordered = members.sorted { (screens[$0].x, screens[$0].y, $0) < (screens[$1].x, screens[$1].y, $1) }
            for (rank, index) in ordered.enumerated() where rank > 0 {
                ids[index] = screens[index].base + "#\(rank + 1)"
            }
        }
        return ids
    }
}
