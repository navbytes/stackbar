/// Numbers on chart axes and legends: whole numbers as they are, one decimal
/// otherwise, and large ones shortened (`174.4M`, `1.9B`) so a token count
/// fits on an axis.
public enum ChartNumber {
    public static func format(_ value: Double) -> String {
        let magnitude = abs(value)
        for (limit, suffix) in [(1e12, "T"), (1e9, "B"), (1e6, "M"), (1e4, "K")] where magnitude >= limit {
            let scaled = value / (limit == 1e4 ? 1e3 : limit)
            return plain(scaled, decimals: abs(scaled) < 1000 ? 1 : 0) + suffix
        }
        return plain(value, decimals: 1)
    }

    private static func plain(_ value: Double, decimals: Int) -> String {
        if abs(value - value.rounded()) < 0.05 || decimals == 0 { return String(Int(value.rounded())) }
        let factor = 10.0
        let rounded = (value * factor).rounded() / factor
        let whole = Int(rounded)
        let tenth = Int((abs(rounded - Double(whole)) * factor).rounded())
        return (rounded < 0 && whole == 0 ? "-" : "") + "\(whole).\(tenth)"
    }
}

/// Where each day of a `.heatmap` chart goes: week columns, Sunday in row 0,
/// the last value (today) in today's row of the last column.
public struct HeatmapLayout: Equatable, Sendable {
    public let count: Int
    /// Today's weekday, 0 for Sunday through 6 for Saturday.
    public let todayRow: Int

    public init(count: Int, todayRow: Int) {
        self.count = count
        self.todayRow = min(6, max(0, todayRow))
    }

    /// Empty cells before the first day, so the last lands on `todayRow`.
    private var lead: Int { ((todayRow - (count - 1)) % 7 + 7) % 7 }

    public var columns: Int { max(1, (lead + count + 6) / 7) }

    public func cell(_ index: Int) -> (column: Int, row: Int) {
        let position = lead + index
        return (position / 7, position % 7)
    }

    /// 0 for no activity, then 1 to 4 by quartile of the active days, so a
    /// single huge day doesn't wash out the rest.
    public static func levels(_ values: [Double]) -> [Int] {
        let active = values.filter { $0 > 0 }.sorted()
        guard !active.isEmpty else { return values.map { _ in 0 } }
        let cut = { (fraction: Double) in active[min(active.count - 1, Int(Double(active.count - 1) * fraction))] }
        let (q1, q2, q3) = (cut(0.25), cut(0.5), cut(0.75))
        return values.map { value in
            if value <= 0 { return 0 }
            if value <= q1 { return 1 }
            if value <= q2 { return 2 }
            if value <= q3 { return 3 }
            return 4
        }
    }
}
