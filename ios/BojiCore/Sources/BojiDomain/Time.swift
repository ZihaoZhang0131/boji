import Foundation

public protocol AppClock: Sendable {
    var now: Date { get }
    var timeZone: TimeZone { get }
}

public struct SystemClock: AppClock {
    public init() {}
    public var now: Date { Date() }
    public var timeZone: TimeZone { .current }
}

/// A Gregorian calendar day, independent of subsequent device timezone changes.
public struct LocalDay: Codable, Hashable, Comparable, Sendable, CustomStringConvertible {
    public let year: Int
    public let month: Int
    public let day: Int

    public init(year: Int, month: Int, day: Int) throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let parts = DateComponents(year: year, month: month, day: day, hour: 12)
        guard (1...9999).contains(year), let value = calendar.date(from: parts),
              calendar.dateComponents([.year, .month, .day], from: value).year == year,
              calendar.component(.month, from: value) == month,
              calendar.component(.day, from: value) == day else { throw DomainError.invalidDate }
        self.year = year; self.month = month; self.day = day
    }

    public init(_ date: Date, timeZone: TimeZone) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        year = calendar.component(.year, from: date)
        month = calendar.component(.month, from: date)
        day = calendar.component(.day, from: date)
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(year: c.decode(Int.self, forKey: .year), month: c.decode(Int.self, forKey: .month), day: c.decode(Int.self, forKey: .day))
    }

    public var description: String { String(format: "%04d-%02d-%02d", year, month, day) }
    public static func < (lhs: Self, rhs: Self) -> Bool { (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day) }

    public func date(in timeZone: TimeZone) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    public func adding(days: Int) -> Self {
        let zone = TimeZone(secondsFromGMT: 0)!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return Self(calendar.date(byAdding: .day, value: days, to: date(in: zone))!, timeZone: zone)
    }
}

public struct RecordTime: Codable, Equatable, Sendable {
    public var localDay: LocalDay
    public var hour: Int
    public var minute: Int
    public var timeZoneIdentifier: String
    public var instant: Date?

    public init(clock: any AppClock, selectedDay: LocalDay? = nil) {
        let now = clock.now
        let zone = clock.timeZone
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        localDay = selectedDay ?? LocalDay(now, timeZone: zone)
        hour = calendar.component(.hour, from: now)
        minute = calendar.component(.minute, from: now)
        timeZoneIdentifier = zone.identifier
        instant = calendar.date(from: DateComponents(year: localDay.year, month: localDay.month, day: localDay.day, hour: hour, minute: minute))
    }

    public var displayTime: String { String(format: "%02d:%02d", hour, minute) }
}

public struct DateNavigation: Equatable, Sendable {
    public private(set) var selectedDay: LocalDay
    public private(set) var followsToday = true
    public var isEditing = false

    public init(clock: any AppClock) { selectedDay = LocalDay(clock.now, timeZone: clock.timeZone) }
    public mutating func select(_ day: LocalDay) { selectedDay = day; followsToday = false }
    public mutating func returnToToday(clock: any AppClock) {
        followsToday = true
        selectedDay = LocalDay(clock.now, timeZone: clock.timeZone)
    }
    public mutating func refresh(clock: any AppClock) {
        if followsToday && !isEditing { selectedDay = LocalDay(clock.now, timeZone: clock.timeZone) }
    }
}
