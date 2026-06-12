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
    enum SyncStatus: Equatable { case idle, syncing, synced(TimeInterval), failed }

    @Published var now = Date()
    @Published var syncStatus: SyncStatus = .idle

    private var timer: Timer?
    private var ntpOffset: TimeInterval = 0      // 真实时间 = 本地时间 + ntpOffset
    private var currentServer: String
    private var lastSync = Date.distantPast
    private var isSyncing = false

    init() {
        currentServer = UserDefaults.standard.string(forKey: "ntpServer") ?? AppSettings.defaultNTP
        scheduleNextTick()
        sync()
    }

    /// 切换/重设校时服务器并立即校时
    func setServer(_ host: String) {
        let h = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !h.isEmpty else { return }
        currentServer = h
        sync()
    }

    /// 向 NTP 服务器校时，更新偏移
    func sync() {
        if isSyncing { return }
        isSyncing = true
        syncStatus = .syncing
        let server = currentServer
        Task {
            let result = try? await NTPClient.offset(host: server)
            await MainActor.run {
                self.isSyncing = false
                self.lastSync = Date()
                if let off = result {
                    self.ntpOffset = off
                    self.syncStatus = .synced(off)
                } else {
                    self.syncStatus = .failed
                }
            }
        }
    }

    /// 对齐到整秒边界刷新，避免显示相位滞后导致看起来慢一秒
    private func scheduleNextTick() {
        let nowTI = Date().timeIntervalSinceReferenceDate
        // 下一个整秒 + 20ms 余量，确保读到的就是新的整秒
        let delay = floor(nowTI) + 1.0 + 0.02 - nowTI
        let t = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            self.now = Date().addingTimeInterval(self.ntpOffset)
            // 后台每 6 小时自动校准一次
            if Date().timeIntervalSince(self.lastSync) > 6 * 3600 { self.sync() }
            self.scheduleNextTick()
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
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
    @AppStorage("ntpServer") var ntpServer: String = AppSettings.defaultNTP {
        didSet { objectWillChange.send() }
    }
    // 用户新增的自定义 NTP 服务器（换行分隔持久化）
    @AppStorage("customNTPServers") var customServersRaw: String = "" {
        didSet { objectWillChange.send() }
    }
    var customServers: [String] {
        customServersRaw.split(separator: "\n").map(String.init).filter { !$0.isEmpty }
    }
    /// 新增自定义服务器并设为当前；预置/已存在则直接选中，不重复添加
    func addCustomServer(_ host: String) {
        let h = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !h.isEmpty else { return }
        if !AppSettings.ntpServers.contains(where: { $0.0 == h }), !customServers.contains(h) {
            customServersRaw = (customServers + [h]).joined(separator: "\n")
        }
        ntpServer = h
    }

    var timeZone: TimeZone {
        TimeZone(identifier: timeZoneID) ?? TimeZone(identifier: "Asia/Shanghai")!
    }

    static let defaultNTP = "ntp.aliyun.com"

    // 常用 NTP 校时服务器
    static let ntpServers: [(String, String)] = [
        ("ntp.aliyun.com", "阿里云"),
        ("ntp.ntsc.ac.cn", "国家授时中心"),
        ("cn.pool.ntp.org", "NTP Pool 中国"),
        ("time.apple.com", "Apple"),
        ("time.windows.com", "Microsoft"),
        ("time.cloudflare.com", "Cloudflare")
    ]

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
