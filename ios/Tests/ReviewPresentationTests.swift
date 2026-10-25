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
    func testCurvesRenderKnownSeriesAndGaps() throws {
        let clock = Clock(), today = RecordTime(clock: Clock()).localDay
        var state = DatasetSnapshot()
        for (index, kcal) in [1800, 1650, 2000, 0, 2100, 1900, 1850].enumerated() {
            let time = RecordTime(clock: clock, selectedDay: today.adding(days: index - 6))
            var meal = Meal(time: time)
            let estimate = EstimateRevision(recordID: meal.id, inputRevision: 0, source: .manual, items: [FoodItem(name: "整餐", grams: nil, kcal: Decimal(kcal))], totalKcal: Decimal(kcal), createdAt: clock.now)
            meal.currentEstimateID = estimate.id; state.meals.append(meal); state.estimates.append(estimate)
            if let energy = [300, 200, nil, nil, 184, 250, 180][index] {
                var workout = Workout(time: time)
                let snapshot = WorkoutEnergy(weightKG: 70, minutes: 60, intensity: .regular, profileVersionID: nil, kcal: energy, algorithmVersion: "MET-net-v1", createdAt: clock.now)
                workout.energyHistory = [snapshot]; workout.currentEnergyID = snapshot.id; state.workouts.append(workout)
            }
        }
        let days = try ReviewRules.range(ending: today, count: 7, in: state).days
        for (name, scheme) in [("light", ColorScheme.light), ("dark", .dark)] {
            let renderer = ImageRenderer(content: VStack(spacing: 36) {
                ReviewChart(days: days, metric: .intake)
                ReviewChart(days: days, metric: .training)
            }.padding(16).frame(width: 375).background(scheme == .dark ? Color.black : Color.white).environment(\.colorScheme, scheme))
            renderer.scale = 2
            let image = try XCTUnwrap(renderer.uiImage)
            XCTAssertEqual(image.size.width, 375)
            let attachment = XCTAttachment(image: image); attachment.name = "review-curves-fixture-" + name
            attachment.lifetime = .keepAlways; add(attachment)
        }
    }
}
