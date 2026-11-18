import XCTest
@testable import StayAwakeCore

final class ScheduleTests: XCTestCase {
    // Calendar weekday: 1 = Sunday … 7 = Saturday. Bits match that order.
    private let sunday = 1
    private let monday = 2
    private let tuesday = 3
    private let saturday = 7
    private let eightAM = 8 * 60
    private let eightPM = 20 * 60

    func testStandardScheduleMatchesWeekdayWifiWindow() {
        let schedule = Schedule.standard
        XCTAssertEqual(schedule.days, Schedule.weekdays)
        XCTAssertFalse(schedule.allDay)
        XCTAssertEqual(schedule.start, eightAM)
        XCTAssertEqual(schedule.end, eightPM)
        XCTAssertTrue(schedule.wifi)
        XCTAssertFalse(schedule.power)

        XCTAssertNil(schedule.pause(weekday: monday, minute: eightAM, wifiConnected: true, onPower: false))
        XCTAssertNil(schedule.pause(weekday: monday, minute: eightPM - 1, wifiConnected: true, onPower: true))
        // 8:00 PM is the exclusive end of 8:00–20:00, same as the previous app.
        XCTAssertEqual(
            schedule.pause(weekday: monday, minute: eightPM, wifiConnected: true, onPower: true),
            .offSchedule
        )
        XCTAssertEqual(
            schedule.pause(weekday: monday, minute: eightAM - 1, wifiConnected: true, onPower: true),
            .offSchedule
        )
        XCTAssertEqual(
            schedule.pause(weekday: saturday, minute: 12 * 60, wifiConnected: true, onPower: true),
            .offSchedule
        )
        XCTAssertEqual(
            schedule.pause(weekday: sunday, minute: 12 * 60, wifiConnected: true, onPower: true),
            .offSchedule
        )
    }

    func testWifiIsRequiredBeforePowerAndSchedule() {
        let schedule = Schedule.standard
        XCTAssertEqual(
            schedule.pause(weekday: monday, minute: 10 * 60, wifiConnected: false, onPower: false),
            .noWifi
        )
        var powerAndWifi = Schedule.customDefault
        powerAndWifi.wifi = true
        powerAndWifi.power = true
        XCTAssertEqual(
            powerAndWifi.pause(weekday: monday, minute: 10 * 60, wifiConnected: false, onPower: false),
            .noWifi
        )
        XCTAssertEqual(
            powerAndWifi.pause(weekday: monday, minute: 10 * 60, wifiConnected: true, onPower: false),
            .onBattery
        )
        XCTAssertNil(
            powerAndWifi.pause(weekday: monday, minute: 10 * 60, wifiConnected: true, onPower: true)
        )
    }

    func testStandardScheduleDoesNotRequirePower() {
        XCTAssertNil(
            Schedule.standard.pause(weekday: tuesday, minute: 9 * 60, wifiConnected: true, onPower: false)
        )
    }

    func testCustomDefaultIsAlwaysAwake() {
        let schedule = Schedule.customDefault
        XCTAssertEqual(schedule.days, Schedule.everyDay)
        XCTAssertTrue(schedule.allDay)
        XCTAssertFalse(schedule.wifi)
        XCTAssertFalse(schedule.power)
        XCTAssertNil(schedule.pause(weekday: sunday, minute: 3 * 60, wifiConnected: false, onPower: false))
    }

    func testAllDayStillRespectsSelectedDays() {
        let schedule = Schedule(days: Schedule.weekdays, allDay: true, start: eightAM, end: eightPM, wifi: false, power: false)
        XCTAssertNil(schedule.pause(weekday: monday, minute: 0, wifiConnected: false, onPower: false))
        XCTAssertEqual(
            schedule.pause(weekday: sunday, minute: 15 * 60, wifiConnected: true, onPower: true),
            .offSchedule
        )
    }

    func testEqualStartAndEndBehavesAsAllHoursOnSelectedDays() {
        let schedule = Schedule(days: Schedule.weekdays, allDay: false, start: eightAM, end: eightAM, wifi: false, power: false)
        XCTAssertNil(schedule.pause(weekday: monday, minute: 23 * 60, wifiConnected: false, onPower: false))
        XCTAssertEqual(
            schedule.pause(weekday: saturday, minute: eightAM, wifiConnected: true, onPower: true),
            .offSchedule
        )
    }

    func testNoDaysSelectedNeverHolds() {
        let schedule = Schedule(days: 0, allDay: true, start: 0, end: 0, wifi: false, power: false)
        XCTAssertEqual(
            schedule.pause(weekday: monday, minute: 12 * 60, wifiConnected: true, onPower: true),
            .offSchedule
        )
    }

    func testOvernightRangeBelongsToThePreviousDayAfterMidnight() {
        // 22:00–06:00, Monday only.
        let mondayBit = 1 << (monday - 1)
        let schedule = Schedule(days: mondayBit, allDay: false, start: 22 * 60, end: 6 * 60, wifi: false, power: false)
        XCTAssertNil(schedule.pause(weekday: monday, minute: 22 * 60, wifiConnected: false, onPower: false))
        XCTAssertNil(schedule.pause(weekday: monday, minute: 23 * 60 + 59, wifiConnected: false, onPower: false))
        XCTAssertNil(schedule.pause(weekday: tuesday, minute: 0, wifiConnected: false, onPower: false))
        XCTAssertNil(schedule.pause(weekday: tuesday, minute: 6 * 60 - 1, wifiConnected: false, onPower: false))
        XCTAssertEqual(
            schedule.pause(weekday: tuesday, minute: 6 * 60, wifiConnected: true, onPower: true),
            .offSchedule
        )
        XCTAssertEqual(
            schedule.pause(weekday: monday, minute: 21 * 60, wifiConnected: true, onPower: true),
            .offSchedule
        )
        // Tuesday 05:00 belongs to Monday's schedule, so Tuesday-only does not cover it.
        let tuesdayBit = 1 << (tuesday - 1)
        let tuesdayOnly = Schedule(days: tuesdayBit, allDay: false, start: 22 * 60, end: 6 * 60, wifi: false, power: false)
        XCTAssertEqual(
            tuesdayOnly.pause(weekday: tuesday, minute: 5 * 60, wifiConnected: true, onPower: true),
            .offSchedule
        )
        XCTAssertNil(tuesdayOnly.pause(weekday: tuesday, minute: 22 * 60, wifiConnected: false, onPower: false))
        // Sunday 03:00 belongs to Saturday.
        let saturdayBit = 1 << (saturday - 1)
        let saturdayOnly = Schedule(days: saturdayBit, allDay: false, start: 22 * 60, end: 6 * 60, wifi: false, power: false)
        XCTAssertNil(saturdayOnly.pause(weekday: sunday, minute: 3 * 60, wifiConnected: false, onPower: false))
    }

    func testAllowSleepNeverDisablesSleep() {
        XCTAssertFalse(SleepPolicy.shouldDisableSleep(
            mode: .sleep,
            custom: .customDefault,
            weekday: monday,
            minute: 10 * 60,
            wifiConnected: true,
            onPower: true
        ))
    }

    func testStayAwakeUsesTheStandardScheduleNotTheCustomOne() {
        var custom = Schedule.customDefault
        custom.days = 0
        XCTAssertTrue(SleepPolicy.shouldDisableSleep(
            mode: .awake,
            custom: custom,
            weekday: monday,
            minute: 10 * 60,
            wifiConnected: true,
            onPower: false
        ))
        XCTAssertFalse(SleepPolicy.shouldDisableSleep(
            mode: .awake,
            custom: .customDefault,
            weekday: monday,
            minute: 10 * 60,
            wifiConnected: false,
            onPower: true
        ))
    }

    func testByRuleUsesTheCustomSchedule() {
        var custom = Schedule.customDefault
        custom.power = true
        XCTAssertFalse(SleepPolicy.shouldDisableSleep(
            mode: .custom,
            custom: custom,
            weekday: sunday,
            minute: 1,
            wifiConnected: false,
            onPower: false
        ))
        XCTAssertTrue(SleepPolicy.shouldDisableSleep(
            mode: .custom,
            custom: custom,
            weekday: sunday,
            minute: 1,
            wifiConnected: false,
            onPower: true
        ))
    }

    func testHotkeySwitchesAllowSleepAndStayAwakeAndLeavesByRule() {
        XCTAssertEqual(SleepPolicy.modeAfterHotkey(current: .sleep, sleepCurrentlyDisabled: false), .awake)
        XCTAssertEqual(SleepPolicy.modeAfterHotkey(current: .awake, sleepCurrentlyDisabled: true), .sleep)
        XCTAssertEqual(SleepPolicy.modeAfterHotkey(current: .custom, sleepCurrentlyDisabled: true), .sleep)
        XCTAssertEqual(SleepPolicy.modeAfterHotkey(current: .custom, sleepCurrentlyDisabled: false), .awake)
    }

    func testModeRawValuesStayCompatibleWithExistingPreferences() {
        XCTAssertEqual(SleepMode.sleep.rawValue, "sleep")
        XCTAssertEqual(SleepMode.awake.rawValue, "awake")
        XCTAssertEqual(SleepMode.custom.rawValue, "custom")
    }
}
