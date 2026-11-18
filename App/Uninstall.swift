import Foundation
import ServiceManagement

/// `Stay Awake.app/Contents/MacOS/StayAwake --uninstall`
enum Uninstall {
    static let flag = "--uninstall"

    static func run() {
        let client = DaemonClient()
        let restored = client.setDisablesleep(false, waitUpTo: 3)
        let daemon = SMAppService.daemon(plistName: SleepDaemon.plistName)
        do {
            try daemon.unregister()
        } catch {
            write(error: "Could not unregister the helper: \(error.localizedDescription)")
        }
        do {
            try SMAppService.mainApp.unregister()
        } catch {
            write(error: "Could not unregister the app from the user session: \(error.localizedDescription)")
        }
        let message = restored
            ? "Sleep is allowed again (disablesleep 0). The helper and the session registration are removed.\n"
            : "The helper was asked to stop. It sets disablesleep 0 when it exits. Check with: pmset -g\n"
        FileHandle.standardOutput.write(Data(message.utf8))
        FileHandle.standardOutput.write(Data("Delete the Stay Awake app from Applications.\n".utf8))
    }

    private static func write(error line: String) {
        FileHandle.standardError.write(Data((line + "\n").utf8))
    }
}
