import Foundation

/// Long-lived privileged connection to the helper. Kept open so a crash or quit is visible
/// to the helper, which then allows sleep again.
final class DaemonClient {
    private var connection: NSXPCConnection?
    private let lock = NSLock()

    func setDisablesleep(_ disabled: Bool, waitUpTo seconds: TimeInterval = 3) -> Bool {
        let current = openConnection()
        let waiter = Waiter()
        guard let proxy = current.remoteObjectProxyWithErrorHandler({ error in
            NSLog("Stay Awake: helper connection failed: \(error.localizedDescription)")
            waiter.finish(false)
        }) as? SleepDaemonXPC else {
            return false
        }
        proxy.setDisablesleep(disabled) { success, message in
            if !message.isEmpty {
                NSLog("Stay Awake: \(message)")
            }
            waiter.finish(success)
        }
        guard let success = waiter.wait(seconds: seconds) else {
            current.invalidate()
            return false
        }
        return success
    }

    private func openConnection() -> NSXPCConnection {
        lock.lock()
        if let connection {
            lock.unlock()
            return connection
        }
        let created = NSXPCConnection(machServiceName: SleepDaemon.machServiceName, options: .privileged)
        created.remoteObjectInterface = NSXPCInterface(with: SleepDaemonXPC.self)
        created.setCodeSigningRequirement(SleepDaemon.daemonRequirement)
        created.invalidationHandler = { [weak self] in
            self?.clear(created)
        }
        created.interruptionHandler = { [weak self] in
            self?.clear(created)
        }
        connection = created
        lock.unlock()
        created.resume()
        return created
    }

    private func clear(_ conn: NSXPCConnection) {
        lock.lock()
        if connection === conn {
            connection = nil
        }
        lock.unlock()
    }
}

private final class Waiter {
    private let semaphore = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var value = false
    private var done = false

    func finish(_ success: Bool) {
        lock.lock()
        let first = !done
        if first {
            done = true
            value = success
        }
        lock.unlock()
        if first {
            semaphore.signal()
        }
    }

    func wait(seconds: TimeInterval) -> Bool? {
        guard semaphore.wait(timeout: .now() + seconds) == .success else { return nil }
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}
