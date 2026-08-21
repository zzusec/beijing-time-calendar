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

@MainActor
final class Clock: ObservableObject {
    enum SyncStatus: Equatable { case idle, syncing, synced(TimeSyncResult), failed(String) }

    @Published var now = Date()
    @Published var syncStatus: SyncStatus = .idle
    @Published private(set) var lastSyncAt: Date?

    private var timer: Timer?
    private var ntpOffset: TimeInterval = 0      // 真实时间 = 本地时间 + ntpOffset
    private var currentServer: String
    private let timeSyncService: TimeSyncService
    private var syncTask: Task<Void, Never>?
    private var syncGeneration = 0
    private var nextAutomaticSync = Date.distantPast
    private var consecutiveFailures = 0

    init(timeSyncService: TimeSyncService = TimeSyncService()) {
        self.timeSyncService = timeSyncService
        currentServer = UserDefaults.standard.string(forKey: "ntpServer") ?? AppSettings.defaultNTP
        scheduleNextTick()
        sync()
    }

    deinit {
        syncTask?.cancel()
    }

    /// 切换/重设首选校时服务器并立即校时。旧请求即使晚到也不会覆盖新状态。
    func setServer(_ host: String) {
        let h = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !h.isEmpty else { return }
        currentServer = h
        consecutiveFailures = 0
        startSync()
    }

    /// 手动校时会绕过自动重试的退避时间。
    func sync() {
        startSync()
    }

    private func startSync() {
        syncGeneration &+= 1
        let generation = syncGeneration
        let server = currentServer
        syncTask?.cancel()
        syncStatus = .syncing

        let service = timeSyncService
        syncTask = Task { [weak self] in
            do {
                let result = try await service.synchronize(preferredHost: server)
                guard !Task.isCancelled, let self, self.syncGeneration == generation else { return }
                self.syncTask = nil
                self.ntpOffset = result.offset
                self.syncStatus = .synced(result)
                self.lastSyncAt = Date().addingTimeInterval(abs(result.offset) >= 1 ? result.offset : 0)
                self.consecutiveFailures = 0
                self.nextAutomaticSync = Date().addingTimeInterval(3600)
            } catch is CancellationError {
                // 被新的校时请求取代，不更新界面或重试节奏。
            } catch {
                guard !Task.isCancelled, let self, self.syncGeneration == generation else { return }
                self.syncTask = nil
                self.syncStatus = .failed((error as? LocalizedError)?.errorDescription ?? "校时服务暂不可用")
                self.consecutiveFailures += 1
                let delays: [TimeInterval] = [5 * 60, 15 * 60, 30 * 60, 60 * 60]
                let index = min(self.consecutiveFailures - 1, delays.count - 1)
                self.nextAutomaticSync = Date().addingTimeInterval(delays[index])
            }
        }
    }

    /// 对齐到整秒边界刷新。时区不影响秒数；正常情况下秒数始终读取本机时间。
    private func scheduleNextTick() {
        let nowTI = Date().timeIntervalSinceReferenceDate
        // 下一个整秒 + 20ms 余量，确保读到的就是新的整秒
        let delay = floor(nowTI) + 1.0 + 0.02 - nowTI
        let t = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                let systemNow = Date()
                // 系统时钟只存在毫秒级偏移时，不让网络校时改变秒钟显示。
                self.now = systemNow.addingTimeInterval(abs(self.ntpOffset) >= 1 ? self.ntpOffset : 0)
                if systemNow >= self.nextAutomaticSync, self.syncTask == nil { self.startSync() }
                self.scheduleNextTick()
            }
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
            let seconds = abs(ntpOffset) < 1 ? cal.component(.second, from: Date()) : (c.second ?? 0)
            s += String(format: ":%02d", seconds)
        }
        return s
    }
}

/// 距上次校时的相对描述："刚刚 / N 分钟前 / N 小时前"
func relativeAgo(_ seconds: TimeInterval) -> String {
    let m = Int(max(0, seconds) / 60)
    if m < 1 { return "刚刚" }
    if m < 60 { return "\(m) 分钟前" }
    return "\(m / 60) 小时前"
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
    // 是否使用自定义 NTP 服务器（选「自定义」时为 true）
    @AppStorage("ntpUseCustom") var useCustomNTP: Bool = false {
        didSet { objectWillChange.send() }
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
