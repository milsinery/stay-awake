import Foundation

/// Names shared by the app and the helper. The property list in the app bundle uses the same label.
enum SleepDaemon {
    static let machServiceName = "com.milsinery.stay-awake.daemon"
    static let plistName = "com.milsinery.stay-awake.daemon.plist"
    static let clientRequirement = XPCClientRequirement.stayAwakeApp
    static let daemonRequirement = XPCClientRequirement.stayAwakeDaemon
}

/// The only privileged operation. The Bool is not turned into a shell command:
/// `true` is `pmset -a disablesleep 1` and `false` is `pmset -a disablesleep 0`.
@objc protocol SleepDaemonXPC {
    func setDisablesleep(_ disabled: Bool, reply: @escaping (Bool, String) -> Void)
}
