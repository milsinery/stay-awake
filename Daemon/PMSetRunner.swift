import Foundation

/// Runs the one allowed `pmset` invocation. Anything else is refused before a process is created.
enum PMSetRunner {
    static func run(executable: String, arguments: [String]) -> Bool {
        guard DisablesleepCommand.isAllowedInvocation(executable: executable, arguments: arguments) else {
            return false
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return false
        }
        process.waitUntilExit()
        return process.terminationStatus == 0
    }
}
