import Foundation
import Testing
import BojiDomain
import BojiEstimation

struct FixedClock: AppClock {
    var now: Date
    var timeZone: TimeZone
    init(_ iso: String, zone: String = "Asia/Shanghai") {
        now = ISO8601DateFormatter().date(from: iso)!
        timeZone = TimeZone(identifier: zone)!
    }
}

@Test func midnightFollowsTodayButKeepsHistoryAndEditing() throws {
    let before = FixedClock("2026-10-17T15:59:00Z")
    let after = FixedClock("2026-10-17T16:01:00Z")
    var navigation = DateNavigation(clock: before)
    #expect(navigation.selectedDay.description == "2026-10-17")
    navigation.isEditing = true
    navigation.refresh(clock: after)
    #expect(navigation.selectedDay.description == "2026-10-17")
    navigation.isEditing = false
    navigation.refresh(clock: after)
    #expect(navigation.selectedDay.description == "2026-10-18")
    let historic = try LocalDay(year: 2020, month: 2, day: 29)
    navigation.select(historic)
    navigation.refresh(clock: after)
    #expect(navigation.selectedDay == historic)
    navigation.returnToToday(clock: after)
    #expect(navigation.selectedDay.description == "2026-10-18")
}

@Test func recordDateSurvivesTravelAndCodableRoundTrip() throws {
    let shanghai = FixedClock("2026-10-17T16:01:00Z")
    let losAngeles = FixedClock("2026-10-17T16:01:00Z", zone: "America/Los_Angeles")
    let record = RecordTime(clock: shanghai)
    let restored = try JSONDecoder().decode(RecordTime.self, from: JSONEncoder().encode(record))
    #expect(restored.localDay.description == "2026-10-18")
    #expect(restored.timeZoneIdentifier == "Asia/Shanghai")
    #expect(restored.displayTime == "00:01")
    var navigation = DateNavigation(clock: shanghai)
    navigation.refresh(clock: losAngeles)
    #expect(navigation.selectedDay.description == "2026-10-17")
    #expect(restored == record)
}

@Test func backfillUsesSelectedDayAndCurrentTime() throws {
    let day = try LocalDay(year: 2026, month: 1, day: 2)
    let record = RecordTime(clock: FixedClock("2026-10-17T11:23:00Z"), selectedDay: day)
    #expect(record.localDay == day)
    #expect(record.displayTime == "19:23")
    #expect(throws: DomainError.invalidDate) { try LocalDay(year: 2026, month: 2, day: 30) }
}

@Test func unconfiguredProductionServiceCannotInventAnEstimate() async {
    await #expect(throws: DomainError.notConfigured) {
        try await UnconfiguredEstimationService().configuration()
    }
}
