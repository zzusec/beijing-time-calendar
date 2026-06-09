import SwiftUI
import AppKit
import Combine
import ServiceManagement

// MARK: - 开机自启（登录项）

enum LoginItem {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }
    static func set(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
        } catch {
            NSLog("登录项设置失败: \(error.localizedDescription)")
        }
    }
}

@main
struct BeijingTimeCalendarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var clock = Clock()
    @StateObject private var settings = AppSettings()

    var body: some Scene {
        MenuBarExtra {
            CalendarPopover()
                .environmentObject(clock)
                .environmentObject(settings)
        } label: {
            Text(clock.menuBarText(settings: settings))
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}

// MARK: - 时钟

final class Clock: ObservableObject {
    @Published var now = Date()
    private var timer: Timer?

    init() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.now = Date()
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    func menuBarText(settings: AppSettings) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = settings.timeZone
        let c = cal.dateComponents([.month, .day, .hour, .minute, .second, .weekday], from: now)
        let weekday = ["日", "一", "二", "三", "四", "五", "六"][(c.weekday ?? 1) - 1]
        let m = c.month ?? 1, d = c.day ?? 1
        let h = c.hour ?? 0, mi = c.minute ?? 0
        var s = "周\(weekday) \(m)/\(d) "
        s += String(format: "%02d:%02d", h, mi)
        if settings.showSeconds {
            s += String(format: ":%02d", c.second ?? 0)
        }
        return s
    }
}

// MARK: - 设置（持久化）

final class AppSettings: ObservableObject {
    @AppStorage("timeZoneID") var timeZoneID: String = "Asia/Shanghai" {
        didSet { objectWillChange.send() }
    }
    @AppStorage("showSeconds") var showSeconds: Bool = false {
        didSet { objectWillChange.send() }
    }

    var timeZone: TimeZone {
        TimeZone(identifier: timeZoneID) ?? TimeZone(identifier: "Asia/Shanghai")!
    }

    // 常用时区候选
    static let commonZones: [(String, String)] = [
        ("Asia/Shanghai", "北京 / 上海"),
        ("Asia/Hong_Kong", "香港"),
        ("Asia/Taipei", "台北"),
        ("Asia/Tokyo", "东京"),
        ("Asia/Singapore", "新加坡"),
        ("Europe/London", "伦敦"),
        ("Europe/Paris", "巴黎"),
        ("America/New_York", "纽约"),
        ("America/Los_Angeles", "洛杉矶"),
        ("America/Chicago", "芝加哥"),
        ("Australia/Sydney", "悉尼")
    ]
}
