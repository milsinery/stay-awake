import Foundation

/// The only privileged command the helper is allowed to run: `/usr/bin/pmset -a disablesleep 0|1`.
public enum DisablesleepCommand {
    public static let executable = "/usr/bin/pmset"

    public static func arguments(_ disablesleep: Bool) -> [String] {
        ["-a", "disablesleep", disablesleep ? "1" : "0"]
    }

    public static func isAllowedInvocation(executable: String, arguments: [String]) -> Bool {
        executable == Self.executable && (arguments == self.arguments(true) || arguments == self.arguments(false))
    }

    /// Paths that must leave the Mac able to sleep, even if the last request was to stay awake.
    public enum SafetyEvent: String, CaseIterable {
        case unregister
        case uninstall
        case failure
        case appQuit
        case daemonCrash
        case daemonStartup
        case clientDisconnected
    }

    public static func value(forSafetyEvent event: SafetyEvent) -> Int {
        switch event {
        case .unregister, .uninstall, .failure, .appQuit, .daemonCrash, .daemonStartup, .clientDisconnected:
            return 0
        }
    }

    /// A failed request to keep the Mac awake is followed by an explicit 0. A failed 0 is already that request.
    public static func shouldRestoreSleepAfterFailure(requestedDisablesleep: Bool, commandSucceeded: Bool) -> Bool {
        requestedDisablesleep && !commandSucceeded
    }

    /// `pmset -g` prints `SleepDisabled` only after it has been set. The line is absent until then.
    public static func sleepIsDisabled(in pmsetOutput: String) -> Bool {
        pmsetOutput
            .split(separator: "\n")
            .contains { $0.contains("SleepDisabled") && $0.trimmingCharacters(in: .whitespaces).hasSuffix("1") }
    }
}
