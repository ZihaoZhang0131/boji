import XCTest
import BojiDomain
@testable import Boji

final class HomePresentationTests: XCTestCase {
    private struct Clock: AppClock {
        let now = ISO8601DateFormatter().date(from: "2026-10-24T12:00:00Z")!
        let timeZone = TimeZone(identifier: "Asia/Shanghai")!
    }
    func testCalendarWindowCrossesYearLeapDayAndDSTWithoutMissingDates() throws {
        for (date, start, end) in [("2026-01-01", "2025-12-17", "2026-01-16"), ("2024-02-29", "2024-02-14", "2024-03-15"), ("2026-03-08", "2026-02-21", "2026-03-23")] {
            let parts = date.split(separator: "-").map { Int($0)! }
            let center = try LocalDay(year: parts[0], month: parts[1], day: parts[2])
            let dates = HomePresentation.dates(around: center)
            XCTAssertEqual(dates.count, 31); XCTAssertEqual(Set(dates).count, 31)
            XCTAssertEqual(dates.first?.description, start); XCTAssertEqual(dates.last?.description, end)
            XCTAssertEqual(dates[15], center)
            for zone in ["America/Los_Angeles", "Asia/Shanghai"] {
                let timeZone = TimeZone(identifier: zone)!
                XCTAssertEqual(dates.map { LocalDay($0.date(in: timeZone), timeZone: timeZone) }, dates)
            }
        }
    }
    func testCategoriesRespectExplicitNamesAndDoNotInventUnknownContent() {
        var workout = Workout(time: RecordTime(clock: Clock()))
        workout.name = "核心训练"
        workout.exercises = [Exercise(name: "深蹲", kind: .weighted)]
        XCTAssertEqual(HomePresentation.region(workout), .core)
        workout.name = "周末训练"
        workout.exercises.append(Exercise(name: "卧推", kind: .weighted))
        XCTAssertEqual(HomePresentation.region(workout), .full)
        workout.name = "Leg press"; XCTAssertEqual(HomePresentation.region(workout), .lower)
        workout.name = "自由训练"; workout.exercises = []
        XCTAssertEqual(HomePresentation.region(workout), .unknown)
        workout.name = "Tomorrow session"; XCTAssertEqual(HomePresentation.region(workout), .unknown)
        workout.name = "Hardcore session"; XCTAssertEqual(HomePresentation.region(workout), .unknown)
        XCTAssertEqual(HomePresentation.mealCategory("下午茶"), "加餐")
        XCTAssertEqual(HomePresentation.mealCategory("午餐"), "午餐")
        XCTAssertEqual(HomePresentation.mealCategory(nil), "饮食")
        XCTAssertEqual(HomePresentation.mealCategory("旧的自定义餐次"), "饮食")
    }
    func testHomeShowsOnlySavedFactsWhileInputRemainsPrivate() {
        let clock = Clock(), time = RecordTime(clock: Clock())
        var saved = Workout(time: time)
        saved.name = "上肢训练"
        var state = DatasetSnapshot(); state.workouts = [saved]
        let before = ReviewRules.day(time.localDay, in: state)
        var draftWorkout = saved; draftWorkout.name = "下肢训练"
        state.drafts = [RecordDraft(editingRecordID: saved.id, content: .workout(draftWorkout), savedAt: clock.now)]
        let entries = HomePresentation.entries(on: time.localDay, in: state)
        XCTAssertEqual(entries.count, 1)
        if case .workout(let visible) = entries[0].event { XCTAssertEqual(visible, saved) }
        else { XCTFail("Expected saved workout") }
        XCTAssertEqual(ReviewRules.day(time.localDay, in: state), before)
        XCTAssertEqual(state.workouts[0].name, "上肢训练")
        let nextDay = time.localDay.adding(days: 1)
        XCTAssertTrue(HomePresentation.entries(on: nextDay, in: state).isEmpty)
        XCTAssertEqual(state.drafts.count, 1)
        state.workouts = []
        XCTAssertTrue(HomePresentation.entries(on: time.localDay, in: state).isEmpty)
    }
    func testCaloriesHaveNoGroupingAndUnknownIsNotZero() {
        XCTAssertEqual(HomePresentation.number(1850), "1850")
        XCTAssertEqual(HomePresentation.number(nil), "—")
        XCTAssertEqual(HomePresentation.number(0), "0")
    }
}
