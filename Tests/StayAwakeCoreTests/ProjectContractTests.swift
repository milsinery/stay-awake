import XCTest

/// Locks the parts of the Mac app that cannot be executed on Linux:
/// bundle identifiers, signing, the absence of sudo, and the preserved menu behavior.
final class ProjectContractTests: XCTestCase {
    private var root: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func text(_ relativePath: String) throws -> String {
        try String(contentsOf: root.appendingPathComponent(relativePath), encoding: .utf8)
    }

    private func swiftSources(under relativeDirectory: String) throws -> [URL] {
        let directory = root.appendingPathComponent(relativeDirectory)
        guard let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil) else {
            return []
        }
        return enumerator.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
    }

    func testSwiftSourcesDoNotCallSudoOrAppleScript() throws {
        let directories = ["App", "Daemon", "Shared", "Sources"]
        let forbidden = [
            "sudo",
            "osascript",
            "NSAppleScript",
            "administrator privileges",
            "/etc/sudoers",
            "sudoers",
            "/bin/sh",
            "/bin/bash",
            "/bin/zsh",
        ]
        var scanned = 0
        for directory in directories {
            for url in try swiftSources(under: directory) {
                let source = try String(contentsOf: url, encoding: .utf8)
                scanned += 1
                for token in forbidden {
                    XCTAssertFalse(
                        source.contains(token),
                        "\(url.lastPathComponent) contains \(token)"
                    )
                }
            }
        }
        XCTAssertGreaterThan(scanned, 0)
    }

    func testMenuHasNoOpenAtLoginItemAndStillRegistersMainApp() throws {
        let app = try text("App/main.swift")
        let english = try text("App/en.lproj/Localizable.strings")
        let russian = try text("App/ru.lproj/Localizable.strings")
        let combined = app + english + russian
        for phrase in ["Запускать при входе", "Open at Login", "Launch at Login", "launchAtLogin"] {
            XCTAssertFalse(combined.contains(phrase), phrase)
        }
        XCTAssertTrue(app.contains("SMAppService.mainApp.register()"))
        XCTAssertTrue(app.contains("try? SMAppService.mainApp.unregister()"))
        XCTAssertTrue(app.contains("SMAppService.openSystemSettingsLoginItems()"))
        XCTAssertTrue(app.contains("SMAppService.daemon(plistName:"))
    }

    func testPreservedMenuBehaviorMarkers() throws {
        let app = try text("App/main.swift")
        XCTAssertTrue(app.contains("\"Allow Sleep\""))
        XCTAssertTrue(app.contains("\"Stay Awake\""))
        XCTAssertTrue(app.contains("\"By Rule\""))
        XCTAssertTrue(app.contains("\"sun.max.fill\""))
        XCTAssertTrue(app.contains("\"calendar\""))
        XCTAssertTrue(app.contains("\"moon.fill\""))
        XCTAssertTrue(app.contains("kVK_ANSI_S"))
        XCTAssertTrue(app.contains("controlKey | optionKey | cmdKey"))
        XCTAssertTrue(app.contains("withTimeInterval: 10"))
        XCTAssertTrue(app.contains("CWWiFiClient"))
        XCTAssertTrue(app.contains("kIOPMACPowerKey"))
        XCTAssertTrue(app.contains("⌃⌥⌘S"))

        let russian = try text("App/ru.lproj/Localizable.strings")
        XCTAssertTrue(russian.contains("\"Allow Sleep\" = \"Разрешить сон\""))
        XCTAssertTrue(russian.contains("\"Stay Awake\" = \"Не засыпать\""))
        XCTAssertTrue(russian.contains("\"By Rule\" = \"По правилу\""))
        XCTAssertTrue(russian.contains("\"no Wi-Fi\" = \"нет Wi-Fi\""))
        XCTAssertTrue(russian.contains("\"on battery\" = \"работает от батареи\""))
    }

    func testDaemonValidatesTheClientAndOnlyRunsPmset() throws {
        let daemon = try text("Daemon/main.swift")
        XCTAssertTrue(daemon.contains("setCodeSigningRequirement(SleepDaemon.clientRequirement)"))
        XCTAssertTrue(daemon.contains("DisablesleepCommand.executable"))
        XCTAssertTrue(daemon.contains("DisablesleepCommand.arguments"))
        XCTAssertTrue(daemon.contains("isAllowedInvocation"))
        XCTAssertTrue(daemon.contains("SIGTERM"))
        XCTAssertTrue(daemon.contains("daemonStartup"))
        XCTAssertTrue(daemon.contains("clientDisconnected"))
        XCTAssertFalse(daemon.contains("Process()"))
        // The only Process construction goes through the checked runner.
        XCTAssertTrue(daemon.contains("PMSetRunner"))
    }

    func testLaunchDaemonPlistIsAnEmbeddedBundleProgram() throws {
        let plist = try text("Daemon/com.milsinery.stay-awake.daemon.plist")
        XCTAssertTrue(plist.contains("<string>com.milsinery.stay-awake.daemon</string>"))
        XCTAssertTrue(plist.contains("<string>Contents/MacOS/StayAwakeDaemon</string>"))
        XCTAssertTrue(plist.contains("<key>MachServices</key>"))
        XCTAssertTrue(plist.contains("<key>RunAtLoad</key>"))
        XCTAssertTrue(plist.contains("<key>KeepAlive</key>"))
        XCTAssertTrue(plist.contains("<key>SuccessfulExit</key>"))
        XCTAssertTrue(plist.contains("<false/>"))
        XCTAssertFalse(plist.contains("sudo"))
        XCTAssertFalse(plist.contains("ProgramArguments"))
        XCTAssertFalse(plist.contains("/bin/"))
    }

    func testXcodeProjectIdentifiersTeamAndDeveloperIDSigning() throws {
        let project = try text("StayAwake.xcodeproj/project.pbxproj")
        XCTAssertTrue(project.contains("PRODUCT_BUNDLE_IDENTIFIER = com.milsinery.stay-awake;"))
        XCTAssertTrue(project.contains("PRODUCT_BUNDLE_IDENTIFIER = com.milsinery.stay-awake.daemon;"))
        XCTAssertTrue(project.contains("DEVELOPMENT_TEAM = CA23Z5CN46;"))
        XCTAssertTrue(project.contains("\"Developer ID Application\""))
        XCTAssertTrue(project.contains("ENABLE_HARDENED_RUNTIME = YES;"))
        XCTAssertTrue(project.contains("CODE_SIGN_INJECT_BASE_ENTITLEMENTS = NO;"))
        XCTAssertTrue(project.contains("--timestamp"))
        XCTAssertTrue(project.contains("MACOSX_DEPLOYMENT_TARGET = 13.0;"))
        XCTAssertTrue(project.contains("Contents/Library/LaunchDaemons"))
        XCTAssertTrue(project.contains("com.milsinery.stay-awake.daemon.plist"))

        let export = try text("Distribution/ExportOptions.plist")
        XCTAssertTrue(export.contains("<string>developer-id</string>"))
        XCTAssertTrue(export.contains("<string>CA23Z5CN46</string>"))
        XCTAssertTrue(export.contains("<string>Developer ID Application</string>"))

        let info = try text("App/Info.plist")
        XCTAssertTrue(info.contains("<string>com.milsinery.stay-awake</string>"))
        XCTAssertTrue(info.contains("<key>LSUIElement</key>"))
        XCTAssertTrue(info.contains("<true/>"))
        XCTAssertTrue(info.contains("<string>13.0</string>"))
        XCTAssertFalse(info.contains("local.sleep-toggle"))
    }

    func testBuildScriptIsAnXcodebuildWrapper() throws {
        let script = try text("build.sh")
        XCTAssertTrue(script.contains("xcodebuild"))
        XCTAssertFalse(script.contains("swiftc"))
        XCTAssertFalse(script.contains("codesign --force --sign -"))
        XCTAssertFalse(script.contains("sudo"))
    }

    func testUninstallRestoresSleepAndUnregisters() throws {
        let source = try text("App/Uninstall.swift")
        XCTAssertTrue(source.contains("setDisablesleep(false"))
        XCTAssertTrue(source.contains("SMAppService.daemon"))
        XCTAssertTrue(source.contains(".unregister()"))
        XCTAssertTrue(source.contains("SMAppService.mainApp.unregister()"))
        XCTAssertTrue(source.contains("--uninstall"))
    }
}
