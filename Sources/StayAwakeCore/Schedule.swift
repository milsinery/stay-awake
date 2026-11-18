import Foundation

/// When Stay Awake holds: selected days and hours, optionally only on Wi-Fi or on power.
/// Weekday numbers match `Calendar`: 1 is Sunday. Day bits use the same order, Sunday = bit 0.
public struct Schedule: Equatable {
    public var days: Int
    public var allDay: Bool
    public var start: Int // minutes from midnight
    public var end: Int
    public var wifi: Bool
    public var power: Bool

    public static let weekdays = 0b0111110
    public static let everyDay = 0b1111111
    public static let standard = Schedule(days: weekdays, allDay: false, start: 8 * 60, end: 20 * 60, wifi: true, power: false)
    public static let customDefault = Schedule(days: everyDay, allDay: true, start: 8 * 60, end: 20 * 60, wifi: false, power: false)

    public init(days: Int, allDay: Bool, start: Int, end: Int, wifi: Bool, power: Bool) {
        self.days = days
        self.allDay = allDay
        self.start = start
        self.end = end
        self.wifi = wifi
        self.power = power
    }

    public func hasDay(_ weekday: Int) -> Bool {
        days & (1 << (weekday - 1)) != 0
    }

    public enum Pause: Equatable {
        case noWifi
        case onBattery
        case offSchedule
    }

    /// Wi-Fi is checked before power, and power before the clock. The first miss wins.
    public func pause(weekday: Int, minute: Int, wifiConnected: Bool, onPower: Bool) -> Pause? {
        if wifi && !wifiConnected { return .noWifi }
        if power && !onPower { return .onBattery }
        if !isScheduled(weekday: weekday, minute: minute) { return .offSchedule }
        return nil
    }

    public func isScheduled(weekday: Int, minute: Int) -> Bool {
        if allDay || start == end { return hasDay(weekday) }
        if start < end { return hasDay(weekday) && (start..<end).contains(minute) }
        // Overnight range: the part after midnight belongs to the previous day's schedule.
        if minute >= start { return hasDay(weekday) }
        if minute < end { return hasDay(weekday == 1 ? 7 : weekday - 1) }
        return false
    }
}

public enum SleepMode: String, Equatable {
    case sleep, awake, custom
}

public enum SleepPolicy {
    public static func shouldDisableSleep(
        mode: SleepMode,
        custom: Schedule,
        weekday: Int,
        minute: Int,
        wifiConnected: Bool,
        onPower: Bool
    ) -> Bool {
        let schedule: Schedule
        switch mode {
        case .sleep:
            return false
        case .awake:
            schedule = .standard
        case .custom:
            schedule = custom
        }
        return schedule.pause(
            weekday: weekday,
            minute: minute,
            wifiConnected: wifiConnected,
            onPower: onPower
        ) == nil
    }

    /// ⌃⌥⌘S switches between Allow Sleep and Stay Awake. By Rule leaves the menu for one of those two.
    public static func modeAfterHotkey(current: SleepMode, sleepCurrentlyDisabled: Bool) -> SleepMode {
        switch current {
        case .sleep:
            return .awake
        case .awake:
            return .sleep
        case .custom:
            return sleepCurrentlyDisabled ? .sleep : .awake
        }
    }
}
