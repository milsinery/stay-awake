import Foundation

/// Code-signing requirements for the XPC connection between the menu bar app and the root helper.
/// `anchor apple generic` plus the team prefix accepts both Apple Development and Developer ID
/// certificates from this team, so a local run and a notarized build satisfy the same check.
public enum XPCClientRequirement {
    public static let appBundleID = "com.milsinery.stay-awake"
    public static let daemonBundleID = "com.milsinery.stay-awake.daemon"
    public static let teamID = "CA23Z5CN46"

    public static let stayAwakeApp = requirement(identifier: appBundleID, teamID: teamID)
    public static let stayAwakeDaemon = requirement(identifier: daemonBundleID, teamID: teamID)

    public static func requirement(identifier: String, teamID: String) -> String {
        "identifier \"\(identifier)\" and anchor apple generic and certificate leaf[subject.OU] = \"\(teamID)\""
    }
}
