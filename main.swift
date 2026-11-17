import AppKit
import Carbon
import CoreWLAN
import IOKit.ps
import ServiceManagement
import SwiftUI

// Strings come from <lang>.lproj/Localizable.strings; the English text is the key and the fallback.
private func L(_ key: String) -> String {
    NSLocalizedString(key, comment: "")
}

// The language the app's strings are shown in, so dates and times match the text around them.
private let appLocale = Locale(identifier: Bundle.main.preferredLocalizations.first ?? "en")

private enum Mode: String {
    case sleep, awake, custom
}

// When Stay Awake holds: on the selected days and hours, optionally only on Wi-Fi or on power.
private struct Schedule {
    var days: Int // bit (weekday - 1) per day, Sunday = bit 0
    var allDay: Bool
    var start: Int // minutes from midnight
    var end: Int
    var wifi: Bool
    var power: Bool

    static let weekdays = 0b0111110
    static let everyDay = 0b1111111
    static let standard = Schedule(days: weekdays, allDay: false, start: 8 * 60, end: 20 * 60, wifi: true, power: false)
    static let customDefault = Schedule(days: everyDay, allDay: true, start: 8 * 60, end: 20 * 60, wifi: false, power: false)

    static var custom: Schedule {
        let defaults = UserDefaults.standard
        return Schedule(
            days: defaults.object(forKey: "customDays") as? Int ?? customDefault.days,
            allDay: defaults.object(forKey: "customAllDay") as? Bool ?? customDefault.allDay,
            start: defaults.object(forKey: "customStart") as? Int ?? customDefault.start,
            end: defaults.object(forKey: "customEnd") as? Int ?? customDefault.end,
            wifi: defaults.object(forKey: "customWifi") as? Bool ?? customDefault.wifi,
            power: defaults.object(forKey: "customPower") as? Bool ?? customDefault.power
        )
    }

    func hasDay(_ weekday: Int) -> Bool {
        days & (1 << (weekday - 1)) != 0
    }

    func pauseReason(at now: Date, wifiConnected: () -> Bool, onPower: () -> Bool) -> String? {
        if wifi && !wifiConnected() { return L("no Wi-Fi") }
        if power && !onPower() { return L("on battery") }
        if !isScheduled(at: now) { return L("off schedule") }
        return nil
    }

    private func isScheduled(at now: Date) -> Bool {
        let calendar = Calendar.current
        let weekday = calendar.component(.weekday, from: now)
        let minute = calendar.component(.hour, from: now) * 60 + calendar.component(.minute, from: now)
        if allDay || start == end { return hasDay(weekday) }
        if start < end { return hasDay(weekday) && (start..<end).contains(minute) }
        // Overnight range: the part after midnight belongs to the previous day's schedule.
        if minute >= start { return hasDay(weekday) }
        if minute < end { return hasDay(weekday == 1 ? 7 : weekday - 1) }
        return false
    }

    var summary: String {
        if days == 0 { return L("No days selected") }
        var parts: [String] = []
        if days == Schedule.everyDay && allDay {
            parts.append(L("Always"))
        } else {
            parts.append(daysSummary + (allDay ? "" : " \(Schedule.time(start)) – \(Schedule.time(end))"))
        }
        if wifi { parts.append(L("on Wi-Fi")) }
        if power { parts.append(L("on power")) }
        return parts.joined(separator: ", ")
    }

    private var daysSummary: String {
        switch days {
        case Schedule.everyDay: return L("Every day")
        case Schedule.weekdays: return L("Weekdays")
        case 0b1000001: return L("Weekends")
        default: return Schedule.orderedWeekdays.filter(hasDay).map(Schedule.dayName).joined(separator: ", ")
        }
    }

    // Weekdays in the order of the user's calendar, e.g. Monday first.
    static var orderedWeekdays: [Int] {
        let first = Calendar.current.firstWeekday
        return (0..<7).map { (first - 1 + $0) % 7 + 1 }
    }

    // Two letters, capitalised: "Mo" in English, "Пн" in Russian.
    static func dayName(_ weekday: Int) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = appLocale
        return String(calendar.shortWeekdaySymbols[weekday - 1].prefix(2)).capitalized(with: appLocale)
    }

    // AM/PM symbols in the app's language, but the 12/24-hour cycle the user picked in System Settings.
    static func time(_ minutes: Int) -> String {
        let formatter = DateFormatter()
        formatter.locale = appLocale
        formatter.dateFormat = DateFormatter.dateFormat(fromTemplate: "jmm", options: 0, locale: .current)
        let date = Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: Date()) ?? Date()
        return formatter.string(from: date)
    }
}

// One hovered row for the whole menu: rows that move under a still cursor never get a hover-exit event.
private final class Hover: ObservableObject {
    static let shared = Hover()
    @Published var row: String?
}

// A menu row drawn as a SwiftUI view: picking a regular menu item would close the menu.
// Quit uses it too, so all rows share one text inset.
private struct MenuRow: View {
    var mode: Mode?
    let title: String
    var shortcut: String?
    var subtitle: () -> String? = { nil }
    let action: () -> Void
    @AppStorage("mode") private var current = Mode.awake.rawValue
    // A plain observable instead of @State: the command line toolchain lacks the SwiftUI macro plugin.
    @ObservedObject private var hover = Hover.shared

    var body: some View {
        let isSelected = mode?.rawValue == current
        let isHovered = hover.row == title
        let secondary = isHovered ? Color.white.opacity(0.8) : Color.secondary
        Button(action: action) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 12)
                    .opacity(isSelected ? 1 : 0)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                    if let subtitle = subtitle() {
                        Text(subtitle)
                            .font(.system(size: 11))
                            .foregroundStyle(secondary)
                    }
                }
                Spacer()
                if let shortcut {
                    Text(shortcut).foregroundStyle(secondary)
                }
            }
            .font(.system(size: 13))
            .foregroundStyle(isHovered ? Color.white : Color.primary)
            .padding(.horizontal, 9)
            .padding(.vertical, 3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 5).fill(isHovered ? Color.accentColor : Color.clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(maxHeight: .infinity, alignment: .top)
        .onHover { isInside in
            if isInside {
                hover.row = title
            } else if hover.row == title {
                hover.row = nil
            }
        }
        .padding(.horizontal, 5)
        .frame(width: 290)
    }
}

// The system switch draws grey inside a menu, which never becomes the key window, so draw our own.
private struct MenuSwitchStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            Capsule()
                .fill(configuration.isOn ? Color.accentColor : Color.primary.opacity(0.15))
                .frame(width: 32, height: 18)
                .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                    Circle()
                        .fill(Color.white)
                        .shadow(color: .black.opacity(0.25), radius: 1, y: 0.5)
                        .padding(2)
                }
                .animation(.easeOut(duration: 0.15), value: configuration.isOn)
        }
        .buttonStyle(.plain)
    }
}

// Custom settings, shown right in the menu under the Custom row while Custom is selected.
// Each part is its own menu item: the hours are hidden as an item, so no view ever changes height.
private struct CustomScheduleMenuView: View {
    enum Part { case days, hours, conditions }

    let part: Part
    @AppStorage("customDays") private var days = Schedule.customDefault.days
    @AppStorage("customAllDay") private var allDay = Schedule.customDefault.allDay
    @AppStorage("customStart") private var start = Schedule.customDefault.start
    @AppStorage("customEnd") private var end = Schedule.customDefault.end
    @AppStorage("customWifi") private var wifi = Schedule.customDefault.wifi
    @AppStorage("customPower") private var power = Schedule.customDefault.power

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            switch part {
            case .days:
                HStack(spacing: 4) {
                    ForEach(Schedule.orderedWeekdays, id: \.self) { weekday in
                        dayButton(weekday)
                    }
                }
                .padding(.bottom, 2)
                switchRow(L("All day"), isOn: $allDay)
            case .hours:
                timeRow(L("From"), minutes: $start)
                timeRow(L("To"), minutes: $end)
            case .conditions:
                switchRow(L("Only on Wi-Fi"), isOn: $wifi)
                switchRow(L("Only on power adapter"), isOn: $power)
            }
        }
        .font(.system(size: 13))
        .padding(.leading, 32)
        .padding(.trailing, 14)
        .padding(.vertical, 3)
        .frame(width: 290)
    }

    private func dayButton(_ weekday: Int) -> some View {
        let bit = 1 << (weekday - 1)
        let isOn = days & bit != 0
        return Button {
            days ^= bit
        } label: {
            Text(Schedule.dayName(weekday))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(isOn ? Color.white : Color.primary)
                .frame(maxWidth: .infinity, minHeight: 24)
                .background(RoundedRectangle(cornerRadius: 6).fill(isOn ? Color.accentColor : Color.primary.opacity(0.08)))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func switchRow(_ title: String, isOn: Binding<Bool>) -> some View {
        HStack {
            Text(title)
            Spacer()
            Toggle(title, isOn: isOn)
                .labelsHidden()
                .toggleStyle(MenuSwitchStyle())
        }
    }

    // Arrows instead of a time field: a menu doesn't pass keyboard input to text fields.
    private func timeRow(_ title: String, minutes: Binding<Int>) -> some View {
        HStack(spacing: 4) {
            Text(title)
            Spacer()
            stepButton("chevron.left") { minutes.wrappedValue = (minutes.wrappedValue + 1410) % 1440 }
            Text(Schedule.time(minutes.wrappedValue))
                .monospacedDigit()
                .frame(width: 70)
            stepButton("chevron.right") { minutes.wrappedValue = (minutes.wrappedValue + 30) % 1440 }
        }
    }

    private func stepButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 22, height: 22)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.08)))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let sleepItem = NSMenuItem()
    private let awakeItem = NSMenuItem()
    private let customItem = NSMenuItem()
    private let customDaysItem = NSMenuItem()
    private let customHoursItem = NSMenuItem()
    private let customConditionsItem = NSMenuItem()
    private let quitItem = NSMenuItem()
    private var timer: Timer?
    private var hotKeyRef: EventHotKeyRef?

    private var mode: Mode {
        get { UserDefaults.standard.string(forKey: "mode").flatMap(Mode.init) ?? .awake }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "mode") }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let hasShortcut = registerHotKey()
        let select: (Mode) -> () -> Void = { mode in
            { [weak self] in
                self?.mode = mode
                self?.apply(askPassword: true)
            }
        }
        sleepItem.view = NSHostingView(rootView: MenuRow(
            mode: .sleep, title: L("Allow Sleep"), shortcut: hasShortcut ? "⌃⌥⌘S" : nil,
            subtitle: { L("macOS default") }, action: select(.sleep)
        ))
        awakeItem.view = NSHostingView(rootView: MenuRow(
            mode: .awake, title: L("Stay Awake"), subtitle: { Schedule.standard.summary }, action: select(.awake)
        ))
        // While By Rule is selected, the settings below show the rule instead of a subtitle.
        customItem.view = NSHostingView(rootView: MenuRow(
            mode: .custom, title: L("By Rule"),
            subtitle: { UserDefaults.standard.string(forKey: "mode") == Mode.custom.rawValue ? nil : Schedule.custom.summary },
            action: select(.custom)
        ))
        customDaysItem.view = NSHostingView(rootView: CustomScheduleMenuView(part: .days))
        customHoursItem.view = NSHostingView(rootView: CustomScheduleMenuView(part: .hours))
        customConditionsItem.view = NSHostingView(rootView: CustomScheduleMenuView(part: .conditions))
        quitItem.view = NSHostingView(rootView: MenuRow(title: L("Quit"), shortcut: "⌘Q") { NSApp.terminate(nil) })

        let menu = NSMenu()
        menu.delegate = self
        menu.addItem(sleepItem)
        menu.addItem(awakeItem)
        menu.addItem(.separator())
        menu.addItem(customItem)
        menu.addItem(customDaysItem)
        menu.addItem(customHoursItem)
        menu.addItem(customConditionsItem)
        menu.addItem(.separator())
        menu.addItem(quitItem)
        statusItem.menu = menu

        registerLoginItem()
        apply(askPassword: false)
        // Wi-Fi, power and the clock change on their own, so re-check them regularly.
        timer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            self?.apply(askPassword: false)
        }
        // Mode and Custom settings take effect as soon as they change in the menu.
        NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.apply(askPassword: false)
        }
    }

    // Global ⌃⌥⌘S via Carbon: works from any app and needs no Accessibility permission.
    private func registerHotKey() -> Bool {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
            guard let userData else { return noErr }
            Unmanaged<AppDelegate>.fromOpaque(userData).takeUnretainedValue().toggleMode()
            return noErr
        }, 1, &eventType, Unmanaged.passUnretained(self).toOpaque(), nil)

        let status = RegisterEventHotKey(
            UInt32(kVK_ANSI_S),
            UInt32(controlKey | optionKey | cmdKey),
            EventHotKeyID(signature: OSType(0x534C_5450), id: 1),
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        return status == noErr
    }

    // CoreWLAN instead of NWPathMonitor(.wifi): with a VPN active the latter reports Wi-Fi as unavailable.
    private func isWifiConnected() -> Bool {
        guard let wifi = CWWiFiClient.shared().interface(), wifi.powerOn() else { return false }
        return wifi.wlanChannel() != nil
    }

    private func isOnPower() -> Bool {
        IOPSGetProvidingPowerSourceType(nil)?.takeRetainedValue() as String? == kIOPMACPowerKey
    }

    private func pauseReason() -> String? {
        let schedule: Schedule
        switch mode {
        case .sleep: return nil
        case .awake: schedule = .standard
        case .custom: schedule = .custom
        }
        return schedule.pauseReason(at: Date(), wifiConnected: isWifiConnected, onPower: isOnPower)
    }

    func menuDidClose(_ menu: NSMenu) {
        Hover.shared.row = nil
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        apply(askPassword: false)
    }

    private func isSleepDisabled() -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        process.arguments = ["-g"]
        let pipe = Pipe()
        process.standardOutput = pipe
        guard (try? process.run()) != nil else { return false }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        // The SleepDisabled line is absent until disablesleep has been set once.
        return String(decoding: data, as: UTF8.self)
            .split(separator: "\n")
            .contains { $0.contains("SleepDisabled") && $0.trimmingCharacters(in: .whitespaces).hasSuffix("1") }
    }

    // The shortcut only switches between Allow Sleep and Stay Awake; Custom is left to the menu.
    private func toggleMode() {
        switch mode {
        case .sleep: mode = .awake
        case .awake: mode = .sleep
        case .custom: mode = isSleepDisabled() ? .sleep : .awake
        }
        apply(askPassword: true)
    }

    private func apply(askPassword: Bool) {
        let reason = pauseReason()
        let disabled = mode != .sleep && reason == nil
        if disabled != isSleepDisabled() {
            setSleepDisabled(disabled, askPassword: askPassword)
        }
        refresh(pauseReason: reason)
    }

    private func setSleepDisabled(_ disabled: Bool, askPassword: Bool) {
        let value = disabled ? 1 : 0
        if !runPasswordlessSudo(value) && askPassword {
            // No sudoers rule installed: ask for the admin password in the standard system dialog.
            let script = "do shell script \"/usr/bin/pmset -a disablesleep \(value)\" with administrator privileges"
            var error: NSDictionary?
            NSAppleScript(source: script)?.executeAndReturnError(&error)
        }
    }

    // Succeeds only with the rule from stay-awake.sudoers; -n fails instead of prompting.
    private func runPasswordlessSudo(_ value: Int) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
        process.arguments = ["-n", "/usr/bin/pmset", "-a", "disablesleep", String(value)]
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return false }
        process.waitUntilExit()
        return process.terminationStatus == 0
    }

    private func refresh(pauseReason: String?) {
        let disabled = isSleepDisabled()
        // The calendar stands in for the sun when it's the By Rule mode keeping the Mac awake.
        let symbol = !disabled ? "moon.fill" : mode == .custom ? "calendar" : "sun.max.fill"
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: disabled ? L("Awake") : L("Sleep"))
        image?.isTemplate = true
        statusItem.button?.image = image
        if let pauseReason {
            statusItem.button?.toolTip = String(format: L("Paused: %@"), pauseReason)
        } else if disabled {
            statusItem.button?.toolTip = mode == .custom
                ? L("Mac stays awake by your rule, even with the lid closed")
                : L("Mac stays awake, even with the lid closed")
        } else {
            statusItem.button?.toolTip = L("Mac sleeps as usual")
        }

        customDaysItem.isHidden = mode != .custom
        customHoursItem.isHidden = mode != .custom || Schedule.custom.allDay
        customConditionsItem.isHidden = mode != .custom
        resizeMenuViews()
        // SwiftUI redraws the rows on the next run loop pass, so measure again once it has.
        DispatchQueue.main.async { self.resizeMenuViews() }
    }

    // The Custom row changes height as its subtitle comes and goes; the open menu re-lays out to the new size.
    private func resizeMenuViews() {
        for item in [sleepItem, awakeItem, customItem, customDaysItem, customHoursItem, customConditionsItem, quitItem] {
            guard let view = item.view else { continue }
            view.layoutSubtreeIfNeeded()
            let size = view.fittingSize
            guard view.frame.size != size else { continue }
            view.frame.size = size
            item.menu?.itemChanged(item)
        }
    }

    // The rule only works while the app runs, so it adds itself to Login Items on every launch.
    private func registerLoginItem() {
        let path = Bundle.main.bundlePath
        // Re-register after a move or rename so Login Items points at this copy, not a stale path.
        if UserDefaults.standard.string(forKey: "loginItemPath") != path {
            try? SMAppService.mainApp.unregister()
        }
        guard SMAppService.mainApp.status != .enabled else { return }
        do {
            try SMAppService.mainApp.register()
            UserDefaults.standard.set(path, forKey: "loginItemPath")
        } catch {
            NSLog("Stay Awake: login item registration failed: \(error.localizedDescription)")
        }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
