import StackbarProtocol

/// Pairs saved window placements with the windows on screen now, the same
/// way on the Mac and in `SimulatedSystem`.
///
/// Per app, a placement first takes a window with the same (non-empty)
/// title, then the remaining placements take the remaining windows in order:
/// the app's frontmost unmatched window goes to its lowest unmatched
/// ordinal. A placement with no window left is missing; a window no
/// placement claims stays where it is.
public enum WindowMatcher {
    public struct Assignment: Equatable, Sendable {
        /// Index into the placements.
        public var placement: Int
        /// Index into the windows.
        public var window: Int
    }

    /// `assignments` in placement order; `missing` holds placement indices.
    public static func match(_ placements: [WindowPlacement], to windows: [WindowInfo]) -> (assignments: [Assignment], missing: [Int]) {
        var assignments: [Assignment] = []
        var missing: [Int] = []
        var taken = Set<Int>()
        var byApp: [String: [Int]] = [:]
        for index in windows.indices.sorted(by: { windows[$0].order < windows[$1].order }) {
            byApp[windows[index].appID, default: []].append(index)
        }
        var appOrder: [String] = []
        var placementsByApp: [String: [Int]] = [:]
        for index in placements.indices {
            let app = placements[index].appID
            if placementsByApp[app] == nil { appOrder.append(app) }
            placementsByApp[app, default: []].append(index)
        }
        for app in appOrder {
            let candidates = byApp[app] ?? []
            let wanted = placementsByApp[app, default: []].sorted { placements[$0].ordinal < placements[$1].ordinal }
            var unmatched: [Int] = []
            for placement in wanted {
                let title = placements[placement].title
                if !title.isEmpty, let window = candidates.first(where: { !taken.contains($0) && windows[$0].title == title }) {
                    taken.insert(window)
                    assignments.append(Assignment(placement: placement, window: window))
                } else {
                    unmatched.append(placement)
                }
            }
            for placement in unmatched {
                if let window = candidates.first(where: { !taken.contains($0) }) {
                    taken.insert(window)
                    assignments.append(Assignment(placement: placement, window: window))
                } else {
                    missing.append(placement)
                }
            }
        }
        return (assignments.sorted { $0.placement < $1.placement }, missing.sorted())
    }
}
