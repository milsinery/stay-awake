import XCTest
@testable import StayAwakeCore

final class DisablesleepTests: XCTestCase {
    func testCommandIsOnlyPmsetDisablesleepZeroOrOne() {
        XCTAssertEqual(DisablesleepCommand.executable, "/usr/bin/pmset")
        XCTAssertEqual(DisablesleepCommand.arguments(true), ["-a", "disablesleep", "1"])
        XCTAssertEqual(DisablesleepCommand.arguments(false), ["-a", "disablesleep", "0"])
        XCTAssertTrue(DisablesleepCommand.isAllowedInvocation(
            executable: "/usr/bin/pmset",
            arguments: ["-a", "disablesleep", "1"]
        ))
        XCTAssertTrue(DisablesleepCommand.isAllowedInvocation(
            executable: "/usr/bin/pmset",
            arguments: ["-a", "disablesleep", "0"]
        ))
        XCTAssertFalse(DisablesleepCommand.isAllowedInvocation(
            executable: "/bin/sh",
            arguments: ["-c", "pmset -a disablesleep 1"]
        ))
        XCTAssertFalse(DisablesleepCommand.isAllowedInvocation(
            executable: "/usr/bin/sudo",
            arguments: ["-n", "/usr/bin/pmset", "-a", "disablesleep", "1"]
        ))
        XCTAssertFalse(DisablesleepCommand.isAllowedInvocation(
            executable: "/usr/bin/pmset",
            arguments: ["-a", "disablesleep", "2"]
        ))
        XCTAssertFalse(DisablesleepCommand.isAllowedInvocation(
            executable: "/usr/bin/pmset",
            arguments: ["sleep", "0"]
        ))
    }

    func testSafetyEventsAlwaysRequestDisablesleepZero() {
        for event in DisablesleepCommand.SafetyEvent.allCases {
            XCTAssertEqual(DisablesleepCommand.value(forSafetyEvent: event), 0, event.rawValue)
        }
        XCTAssertEqual(
            Set(DisablesleepCommand.SafetyEvent.allCases.map(\.rawValue)),
            ["unregister", "uninstall", "failure", "appQuit", "daemonCrash", "daemonStartup", "clientDisconnected"]
        )
    }

    func testFailedAttemptToDisableSleepFallsBackToAllowingSleep() {
        XCTAssertTrue(DisablesleepCommand.shouldRestoreSleepAfterFailure(
            requestedDisablesleep: true,
            commandSucceeded: false
        ))
        XCTAssertFalse(DisablesleepCommand.shouldRestoreSleepAfterFailure(
            requestedDisablesleep: true,
            commandSucceeded: true
        ))
        XCTAssertFalse(DisablesleepCommand.shouldRestoreSleepAfterFailure(
            requestedDisablesleep: false,
            commandSucceeded: false
        ))
        XCTAssertFalse(DisablesleepCommand.shouldRestoreSleepAfterFailure(
            requestedDisablesleep: false,
            commandSucceeded: true
        ))
    }

    func testPmsetOutputParsingMatchesThePreviousApp() {
        XCTAssertFalse(DisablesleepCommand.sleepIsDisabled(in: ""))
        XCTAssertFalse(DisablesleepCommand.sleepIsDisabled(in: "Currently in use:\n standby 1\n"))
        XCTAssertTrue(DisablesleepCommand.sleepIsDisabled(in: "System-wide power settings:\n SleepDisabled\t1\n"))
        XCTAssertFalse(DisablesleepCommand.sleepIsDisabled(in: " SleepDisabled        0\n"))
        XCTAssertTrue(DisablesleepCommand.sleepIsDisabled(in: "  SleepDisabled 1\n hibernatemode 0\n"))
        XCTAssertFalse(DisablesleepCommand.sleepIsDisabled(in: "SleepDisabled 1 extra\n"))
        // The historical check is "ends with 1", so a trailing 1 after SleepDisabled counts.
        XCTAssertTrue(DisablesleepCommand.sleepIsDisabled(in: "note SleepDisabled is 1"))
    }

    func testClientRequirementPinsTheAppIdentifierAndTeam() {
        XCTAssertEqual(
            XPCClientRequirement.stayAwakeApp,
            "identifier \"com.milsinery.stay-awake\" and anchor apple generic and certificate leaf[subject.OU] = \"CA23Z5CN46\""
        )
        XCTAssertEqual(
            XPCClientRequirement.stayAwakeDaemon,
            "identifier \"com.milsinery.stay-awake.daemon\" and anchor apple generic and certificate leaf[subject.OU] = \"CA23Z5CN46\""
        )
        for requirement in [XPCClientRequirement.stayAwakeApp, XPCClientRequirement.stayAwakeDaemon] {
            XCTAssertFalse(requirement.contains("*"))
            XCTAssertFalse(requirement.contains("sudo"))
            XCTAssertTrue(requirement.contains("anchor apple generic"))
            XCTAssertTrue(requirement.contains("CA23Z5CN46"))
        }
    }
}
