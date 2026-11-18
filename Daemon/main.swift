import Foundation
import Security

/// Root helper installed with `SMAppService.daemon`. It starts at boot, allows sleep immediately
/// (including after launchd restarts it from a crash), and allows sleep again when the app
/// disconnects or launchd stops it. While the app is connected it applies only that app's requests.

private let pmsetQueue = DispatchQueue(label: "com.milsinery.stay-awake.daemon.pmset")

private func requirementIsValid(_ requirement: String) -> Bool {
    var parsed: SecRequirement?
    return SecRequirementCreateWithString(requirement as CFString, [], &parsed) == errSecSuccess && parsed != nil
}

private func applyDisablesleep(_ disabled: Bool) -> Bool {
    pmsetQueue.sync {
        let executable = DisablesleepCommand.executable
        let arguments = DisablesleepCommand.arguments(disabled)
        guard DisablesleepCommand.isAllowedInvocation(executable: executable, arguments: arguments) else {
            NSLog("Stay Awake helper: refused an invocation other than pmset disablesleep 0 or 1")
            return false
        }
        let ok = PMSetRunner.run(executable: executable, arguments: arguments)
        if DisablesleepCommand.shouldRestoreSleepAfterFailure(requestedDisablesleep: disabled, commandSucceeded: ok) {
            _ = PMSetRunner.run(executable: executable, arguments: DisablesleepCommand.arguments(false))
        }
        if !ok {
            NSLog("Stay Awake helper: pmset failed while setting disablesleep \(disabled ? 1 : 0)")
        }
        return ok
    }
}

/// Safety events always request disablesleep 0. The event is recorded so a future change that
/// returns anything else is visible in the log instead of leaving the Mac awake.
private func restoreSleep(_ event: DisablesleepCommand.SafetyEvent) {
    if DisablesleepCommand.value(forSafetyEvent: event) != 0 {
        NSLog("Stay Awake helper: safety event \(event.rawValue) must set disablesleep 0")
    }
    if !applyDisablesleep(false) {
        _ = applyDisablesleep(false)
    }
}

final class DaemonDelegate: NSObject, NSXPCListenerDelegate, SleepDaemonXPC {
    private var connections = Set<ObjectIdentifier>()
    private let lock = NSLock()

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        // Enforced by XPC on every message. The peer must be Stay Awake, signed by team CA23Z5CN46.
        newConnection.setCodeSigningRequirement(SleepDaemon.clientRequirement)
        newConnection.exportedInterface = NSXPCInterface(with: SleepDaemonXPC.self)
        newConnection.exportedObject = self
        let id = ObjectIdentifier(newConnection)
        lock.lock()
        connections.insert(id)
        lock.unlock()
        newConnection.invalidationHandler = { [weak self] in
            self?.drop(id)
        }
        newConnection.interruptionHandler = { [weak self] in
            self?.drop(id)
        }
        newConnection.resume()
        return true
    }

    func setDisablesleep(_ disabled: Bool, reply: @escaping (Bool, String) -> Void) {
        let ok = applyDisablesleep(disabled)
        reply(ok, ok ? "" : "pmset failed")
    }

    private func drop(_ id: ObjectIdentifier) {
        lock.lock()
        let removed = connections.remove(id) != nil
        let empty = connections.isEmpty
        lock.unlock()
        if removed && empty {
            restoreSleep(.clientDisconnected)
        }
    }
}

guard requirementIsValid(SleepDaemon.clientRequirement), requirementIsValid(SleepDaemon.daemonRequirement) else {
    NSLog("Stay Awake helper: code-signing requirement is malformed")
    restoreSleep(.failure)
    // Clean exit so launchd does not restart a helper that cannot authenticate its client.
    exit(0)
}

signal(SIGTERM, SIG_IGN)
signal(SIGINT, SIG_IGN)
let stop = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
stop.setEventHandler {
    restoreSleep(.unregister)
    exit(0)
}
stop.resume()
let interrupt = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
interrupt.setEventHandler {
    restoreSleep(.unregister)
    exit(0)
}
interrupt.resume()

// launchd restarts this process after a crash (KeepAlive + SuccessfulExit = false).
// Setting 0 here is what clears disablesleep if the previous process died mid-request.
restoreSleep(.daemonStartup)

let listener = NSXPCListener(machServiceName: SleepDaemon.machServiceName)
let delegate = DaemonDelegate()
listener.delegate = delegate
listener.resume()
dispatchMain()
