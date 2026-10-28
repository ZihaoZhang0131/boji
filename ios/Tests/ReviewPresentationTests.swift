import XCTest
import SwiftUI
import BojiDomain
@testable import Boji

@MainActor final class ReviewPresentationTests: XCTestCase {
    private struct Clock: AppClock {
        let now = ISO8601DateFormatter().date(from: "2026-10-25T04:00:00Z")!
        let timeZone = TimeZone(identifier: "Asia/Shanghai")!
    }
    private func day(_ text: String) throws -> LocalDay {
        let parts = text.split(separator: "-").map { Int($0)! }
        return try LocalDay(year: parts[0], month: parts[1], day: parts[2])
    }
    func testTrendRangeDefaultsAndValidation() throws {
        let today = try day("2026-10-25"), range = ReviewTrendRange.recentWeek(ending: try day("2026-10-25"))
        XCTAssertEqual(range.start.description, "2026-10-19"); XCTAssertEqual(range.end, today)
        XCTAssertNil(range.validationError(today: today))
        XCTAssertEqual(ReviewTrendRange.recentWeek(ending: today.adding(days: 1)).start.description, "2026-10-20")
        XCTAssertNil(ReviewTrendRange(start: today.adding(days: -89), end: today).validationError(today: today))
        XCTAssertNotNil(ReviewTrendRange(start: today.adding(days: -90), end: today).validationError(today: today))
        XCTAssertNotNil(ReviewTrendRange(start: today, end: today.adding(days: 1)).validationError(today: today))
        XCTAssertNotNil(ReviewTrendRange(start: today, end: today.adding(days: -1)).validationError(today: today))
        XCTAssertNil(range.validationError(today: today.adding(days: 1)))
    }
    func testCalendarWeeksCrossYearLeapDayAndDSTWithoutGaps() throws {
        for (today, start, end) in [("2026-01-01", "2025-10-06", "2026-01-04"), ("2024-02-29", "2023-12-04", "2024-03-03"), ("2026-03-08", "2025-12-08", "2026-03-08")] {
            let dates = ReviewPresentation.calendarDays(today: try day(today), offset: 0)
            XCTAssertEqual(dates.count, 91); XCTAssertEqual(Set(dates).count, 91)
            XCTAssertEqual(dates.first?.description, start); XCTAssertEqual(dates.last?.description, end)
            let previous = ReviewPresentation.calendarDays(today: try day(today), offset: 1)
            XCTAssertEqual(previous.last?.adding(days: 1), dates.first)
            for zone in ["America/Los_Angeles", "Asia/Shanghai"] {
                let timeZone = TimeZone(identifier: zone)!
                XCTAssertEqual(dates.map { LocalDay($0.date(in: timeZone), timeZone: timeZone) }, dates)
            }
        }
    }
    func testMissingDaysSplitRunsAndZeroIsARealPoint() {
        let runs = ReviewPresentation.runs([nil, 0, 10, nil, 20, .nan, 30, 40, 50])
        XCTAssertEqual(runs.map { $0.map(\.x) }, [[1, 2], [4], [6, 7, 8]])
        XCTAssertTrue(ReviewPresentation.runs([nil, .nan, -1]).isEmpty)
        XCTAssertEqual(ReviewPresentation.ceiling([nil, 0]), 100)
        XCTAssertEqual(ReviewPresentation.ceiling([1850, 2060]), 3000)
    }
    func testChartCoordinatesAndDateDensity() {
        for count in [1, 7, 30, 90] {
            for maximum in [100.0, 400, 3000, 200000] {
                let plot = ReviewChartGeometry(count: count, maximum: maximum, size: CGSize(width: 240, height: 160), inset: 8)
                XCTAssertEqual(plot.y(0), 152)
                XCTAssertEqual(plot.y(maximum), 8)
                XCTAssertEqual(plot.y(maximum / 2), 80)
                XCTAssertEqual(plot.point(.init(x: 0, y: 0)).y, plot.baseline)
                XCTAssertEqual(plot.x(0) + plot.x(Double(count - 1)), 240, accuracy: 0.001)
                XCTAssertGreaterThan(plot.x(0) - plot.slot * 0.3, 0)
                XCTAssertLessThan(plot.x(Double(count - 1)) + plot.slot * 0.3, 240)
            }
            let indices = ReviewChartGeometry.labelIndices(count: count, accessibility: false)
            XCTAssertEqual(indices.count, count <= 7 ? count : 3)
            XCTAssertEqual(Set(indices).count, indices.count)
            XCTAssertEqual(ReviewChartGeometry.labelIndices(count: count, accessibility: true), count == 1 ? [0] : [0, count - 1])
        }
    }
    func testSmoothCurvePassesThroughSamplesWithoutOvershoot() {
        for values in [[0.0, 200, 2, 300, 0], [10, 10, 10], [0, 0, 10, 10, 0], [1, 30000, 2], [5, 10], [300, 20, 10, 0]] {
            let points = values.enumerated().map { ReviewPresentation.Point(x: Double($0.offset), y: $0.element) }
            let curves = ReviewPresentation.curves(points)
            XCTAssertEqual(curves.map(\.start), Array(points.dropLast())); XCTAssertEqual(curves.map(\.end), Array(points.dropFirst()))
            for curve in curves {
                XCTAssertEqual(curve.c1.x, curve.start.x + 1.0 / 3, accuracy: 1e-10)
                XCTAssertEqual(curve.c2.x, curve.end.x - 1.0 / 3, accuracy: 1e-10)
                for i in 0...100 {
                    let t = Double(i) / 100, q = 1 - t
                    let value = q*q*q*curve.start.y + 3*q*q*t*curve.c1.y + 3*q*t*t*curve.c2.y + t*t*t*curve.end.y
                    XCTAssertGreaterThanOrEqual(value, min(curve.start.y, curve.end.y) - 1e-8)
                    XCTAssertLessThanOrEqual(value, max(curve.start.y, curve.end.y) + 1e-8)
                }
            }
        }
    }
    func testPendingSavedRecordsCountButDraftsTrashAndMissingCaloriesDoNot() {
        let clock = Clock(), time = RecordTime(clock: Clock())
        var state = DatasetSnapshot(), meal = Meal(time: time)
        state.drafts = [RecordDraft(editingRecordID: nil, content: .meal(meal), savedAt: clock.now)]
        XCTAssertNil(ReviewPresentation.earliest(in: state, today: time.localDay))
        state.meals = [meal]; state.workouts = [Workout(time: time)]
        var review = ReviewRules.day(time.localDay, in: state)
        XCTAssertEqual(review.mealCount, 1); XCTAssertEqual(review.workoutCount, 1)
        XCTAssertNil(ReviewPresentation.Metric.intake.value(review)); XCTAssertNil(ReviewPresentation.Metric.training.value(review))
        let estimate = EstimateRevision(recordID: meal.id, inputRevision: 0, source: .manual, items: [FoodItem(name: "整餐", grams: nil, kcal: 0)], totalKcal: 0, createdAt: clock.now)
        meal.currentEstimateID = estimate.id; state.meals = [meal, Meal(time: time)]; state.estimates = [estimate]
        review = ReviewRules.day(time.localDay, in: state)
        XCTAssertEqual(ReviewPresentation.Metric.intake.value(review), 0); XCTAssertTrue(ReviewPresentation.Metric.intake.pending(review))
        state.meals[0].time.localDay = time.localDay.adding(days: -100)
        XCTAssertEqual(ReviewPresentation.earliest(in: state, today: time.localDay), time.localDay.adding(days: -100))
        state.meals[0].deletedAt = clock.now
        XCTAssertEqual(ReviewPresentation.earliest(in: state, today: time.localDay), time.localDay)
        XCTAssertNil(ReviewPresentation.Metric.intake.value(ReviewRules.day(time.localDay, in: state)))
    }
    func testTrainingUsesCurrentSavedNetSnapshotIncludingZero() {
        let clock = Clock(), time = RecordTime(clock: Clock())
        var workout = Workout(time: time), state = DatasetSnapshot()
        let previous = WorkoutEnergy(weightKG: 70, minutes: 60, intensity: .regular, profileVersionID: nil, kcal: 184, algorithmVersion: "MET-net-v1", createdAt: clock.now)
        let current = WorkoutEnergy(weightKG: 70, minutes: 0, intensity: .regular, profileVersionID: nil, kcal: 0, algorithmVersion: "MET-net-v1", createdAt: clock.now)
        workout.energyHistory = [previous, current]; workout.currentEnergyID = current.id
        state.workouts = [workout, Workout(time: time)]
        var review = ReviewRules.day(time.localDay, in: state)
        XCTAssertEqual(ReviewPresentation.Metric.training.value(review), 0)
        XCTAssertTrue(ReviewPresentation.Metric.training.pending(review))
        state.workouts[0].currentEnergyID = previous.id
        review = ReviewRules.day(time.localDay, in: state)
        XCTAssertEqual(ReviewPresentation.Metric.training.value(review), 184)
        XCTAssertEqual(state.workouts[0].energyHistory.count, 2)
    }
    func testChartsRenderKnownSeriesGapsAndZeroAcrossYear() throws {
        let clock = Clock(), today = try day("2026-01-03")
        var state = DatasetSnapshot()
        for (index, kcal) in [1800, 1650, 2000, 0, 2100, 1900, 1850].enumerated() {
            let time = RecordTime(clock: clock, selectedDay: today.adding(days: index - 6))
            var meal = Meal(time: time)
            let estimate = EstimateRevision(recordID: meal.id, inputRevision: 0, source: .manual, items: [FoodItem(name: "整餐", grams: nil, kcal: Decimal(kcal))], totalKcal: Decimal(kcal), createdAt: clock.now)
            meal.currentEstimateID = estimate.id; state.meals.append(meal); state.estimates.append(estimate)
            var workout = Workout(time: time)
            if let energy = [300, 0, nil, 200, 400, nil, 180][index] {
                let snapshot = WorkoutEnergy(weightKG: 70, minutes: 60, intensity: .regular, profileVersionID: nil, kcal: energy, algorithmVersion: "MET-net-v1", createdAt: clock.now)
                workout.energyHistory = [snapshot]; workout.currentEnergyID = snapshot.id
            }
            state.workouts.append(workout)
        }
        for count in [1, 2, 7, 30, 90] {
            let days = try ReviewRules.range(ending: today, count: count, in: state).days
            XCTAssertEqual(days.last?.day.description, "2026-01-03")
            XCTAssertEqual(days.compactMap { ReviewPresentation.Metric.training.value($0) }, count <= 2 ? [180] : [300, 0, 200, 400, 180])
            for width in [320.0, 393.0] {
                for (name, scheme) in [("light", ColorScheme.light), ("dark", .dark)] {
                    for size in [DynamicTypeSize.large, .xxxLarge, .accessibility5] {
                        let renderer = ImageRenderer(content: ReviewCharts(days: days).padding(16).frame(width: width)
                            .background(scheme == .dark ? Color.black : Color.white)
                            .environment(\.colorScheme, scheme).environment(\.dynamicTypeSize, size))
                        renderer.scale = 2
                        let image = try XCTUnwrap(renderer.uiImage)
                        XCTAssertEqual(image.size.width, width)
                        let attachment = XCTAttachment(image: image)
                        attachment.name = "review-charts-\(count)-\(Int(width))-\(name)" + (size.isAccessibilitySize ? "-largest" : size == .xxxLarge ? "-xxxl" : "")
                        attachment.lifetime = .keepAlways; add(attachment)
                    }
                }
            }
        }
    }
    func testChartsRenderWideValuesAndEmptyStates() throws {
        let clock = Clock(), today = try day("2026-01-03")
        var state = DatasetSnapshot()
        let time = RecordTime(clock: clock, selectedDay: today.adding(days: -6))
        state.meals = [Meal(time: time)]
        // Daily totals may be wide even though each meal respects the 10,000 limit.
        for kcal in Array(repeating: 10000, count: 12) + [3456] {
            var meal = Meal(time: time)
            let estimate = EstimateRevision(recordID: meal.id, inputRevision: 0, source: .manual,
                                            items: [FoodItem(name: "长刻度测试样本", grams: nil, kcal: Decimal(kcal))], totalKcal: Decimal(kcal), createdAt: clock.now)
            meal.currentEstimateID = estimate.id
            state.meals.append(meal); state.estimates.append(estimate)
        }
        var workout = Workout(time: time)
        let energy = WorkoutEnergy(weightKG: 70, minutes: 60, intensity: .regular, profileVersionID: nil, kcal: 300, algorithmVersion: "MET-net-v1", createdAt: clock.now)
        workout.energyHistory = [energy]; workout.currentEnergyID = energy.id; state.workouts = [workout]
        for (scenario, source) in [("wide-values", state), ("empty", DatasetSnapshot())] {
            let days = try ReviewRules.range(ending: today, count: 7, in: source).days
            if scenario == "wide-values" { XCTAssertEqual(ReviewPresentation.Metric.intake.value(days[0]), 123456) }
            for width in [320.0, 393.0] {
                for (name, scheme) in [("light", ColorScheme.light), ("dark", .dark)] {
                    for size in [DynamicTypeSize.large, .accessibility5] {
                        let renderer = ImageRenderer(content: ReviewCharts(days: days).padding(16).frame(width: width)
                            .background(scheme == .dark ? Color.black : Color.white)
                            .environment(\.colorScheme, scheme).environment(\.dynamicTypeSize, size))
                        renderer.scale = 2
                        let image = try XCTUnwrap(renderer.uiImage)
                        XCTAssertEqual(image.size.width, width)
                        let attachment = XCTAttachment(image: image)
                        attachment.name = "review-charts-\(scenario)-\(Int(width))-\(name)" + (size.isAccessibilitySize ? "-largest" : "")
                        attachment.lifetime = .keepAlways; add(attachment)
                    }
                }
            }
        }
    }
}
