import Foundation
import BojiDomain

struct ReviewTrendRange: Equatable {
    let start: LocalDay
    let end: LocalDay
    static func recentWeek(ending today: LocalDay) -> Self {
        Self(start: today.adding(days: -6), end: today)
    }
    func validationError(today: LocalDay) -> String? {
        if start > end { return "起始日期不能晚于终止日期。" }
        if start > today || end > today { return "日期不能晚于今天。" }
        do { _ = try ReviewRules.rangeDayCount(starting: start, ending: end); return nil }
        catch { return "日期区间最多 90 天，请缩短范围。" }
    }
}

/// The marks, grid, and both axes share this plot rectangle.
struct ReviewChartGeometry {
    let count: Int
    let maximum: Double
    let size: CGSize
    let inset: CGFloat
    var baseline: CGFloat { size.height - inset }
    var slot: CGFloat { size.width / CGFloat(max(1, count)) }
    var ticks: [Double] { [maximum, maximum / 2, 0] }
    func x(_ index: Double) -> CGFloat { (index + 0.5) * slot }
    func y(_ value: Double) -> CGFloat { baseline - value / maximum * (size.height - 2 * inset) }
    func point(_ value: ReviewPresentation.Point) -> CGPoint { CGPoint(x: x(value.x), y: y(value.y)) }
    static func labelIndices(count: Int, accessibility: Bool) -> [Int] {
        guard count > 0 else { return [] }
        if count == 1 { return [0] }
        if accessibility { return [0, count - 1] }
        return count <= 7 ? Array(0..<count) : [0, (count - 1) / 2, count - 1]
    }
}

/// Display calculations only. Missing values never become zero or interpolate across a gap.
enum ReviewPresentation {
    enum Metric: String { case intake, training
        var title: String { self == .intake ? "摄入" : "训练消耗" }
        func pending(_ day: DayReview) -> Bool { self == .intake ? day.pendingMeals > 0 : day.pendingWorkouts > 0 }
        func value(_ day: DayReview) -> Double? {
            switch self {
            case .intake: day.mealCount > day.pendingMeals ? NSDecimalNumber(decimal: day.knownIntakeKcal).doubleValue : nil
            case .training: day.workoutCount > day.pendingWorkouts ? Double(day.knownWorkoutKcal) : nil
            }
        }
    }
    struct Point: Equatable { let x: Double; let y: Double }
    struct Curve: Equatable { let start: Point; let c1: Point; let c2: Point; let end: Point }
    static func calendarDays(today: LocalDay, offset: Int) -> [LocalDay] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let weekday = (calendar.component(.weekday, from: today.date(in: calendar.timeZone)) + 5) % 7
        let start = today.adding(days: -weekday - 84 - max(0, offset) * 91)
        return (0..<91).map { start.adding(days: $0) }
    }
    static func earliest(in state: DatasetSnapshot, today: LocalDay) -> LocalDay? {
        (state.activeMeals.map(\.time.localDay) + state.activeWorkouts.map(\.time.localDay)).filter { $0 <= today }.min()
    }
    static func runs(_ values: [Double?]) -> [[Point]] {
        var result: [[Point]] = [], run: [Point] = []
        for (index, value) in values.enumerated() {
            if let value, value.isFinite, value >= 0 { run.append(Point(x: Double(index), y: value)) }
            else if !run.isEmpty { result.append(run); run = [] }
        }
        if !run.isEmpty { result.append(run) }
        return result
    }
    /// Uniform daily samples, PCHIP tangents, converted to cubic Bezier control points.
    static func curves(_ points: [Point]) -> [Curve] {
        guard points.count > 1 else { return [] }
        let slopes = (1..<points.count).map { points[$0].y - points[$0 - 1].y }
        func edge(_ a: Double, _ b: Double) -> Double {
            let m = (3 * a - b) / 2
            if m * a <= 0 { return 0 }
            return a * b <= 0 && abs(m) > 3 * abs(a) ? 3 * a : m
        }
        let tangent = points.indices.map { i -> Double in
            if points.count == 2 { return slopes[0] }
            if i == 0 { return edge(slopes[0], slopes[1]) }
            if i == points.count - 1 { return edge(slopes[i - 1], slopes[i - 2]) }
            let a = slopes[i - 1], b = slopes[i]
            return a * b <= 0 ? 0 : 2 * a * b / (a + b)
        }
        return (1..<points.count).map { i in
            Curve(start: points[i - 1], c1: Point(x: points[i - 1].x + 1 / 3, y: points[i - 1].y + tangent[i - 1] / 3),
                  c2: Point(x: points[i].x - 1 / 3, y: points[i].y - tangent[i] / 3), end: points[i])
        }
    }
    static func ceiling(_ values: [Double?]) -> Double {
        let maximum = values.compactMap { $0 }.filter(\.isFinite).max() ?? 0
        guard maximum > 0 else { return 100 }
        let step = pow(10, floor(log10(maximum)))
        return ceil(maximum / step) * step
    }
    static func period(_ start: LocalDay, _ end: LocalDay) -> String {
        "\(start.year) · \(start.month)/\(start.day) — " + (start.year == end.year ? "" : "\(end.year) · ") + "\(end.month)/\(end.day)"
    }
}
