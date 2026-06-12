import SwiftUI
import AppKit

// MARK: - 日历导航模型

final class CalendarModel: ObservableObject {
    @Published var anchor: Date   // 显示月份内任意一天
    @Published var selected: Date

    private var lastToday = Date()

    init() {
        anchor = Date()
        selected = Date()
    }

    func shiftMonth(_ delta: Int, tz: TimeZone) {
        let cal = CN.gregorian(tz)
        if let d = cal.date(byAdding: .month, value: delta, to: anchor) { anchor = d }
    }

    func goToday() {
        anchor = Date()
        selected = Date()
        lastToday = Date()
    }

    /// 跨午夜时若用户仍停留在「今天」（未手动选其他日期），则让选中跟随到新的今天
    func refreshToday(_ now: Date, tz: TimeZone) {
        let cal = CN.gregorian(tz)
        guard !cal.isDate(now, inSameDayAs: lastToday) else { return }
        if cal.isDate(selected, inSameDayAs: lastToday) { selected = now }
        lastToday = now
    }
}

// MARK: - 主弹窗

struct CalendarPopover: View {
    @EnvironmentObject var clock: Clock
    @EnvironmentObject var settings: AppSettings
    @StateObject private var model = CalendarModel()
    @State private var showSettings = false

    var body: some View {
        VStack(spacing: 0) {
            HeaderView()
            Divider()
            MonthNavBar(model: model)
            WeekdayHeader()
            MonthGrid(model: model)
                .padding(.horizontal, 10)
            Divider().padding(.top, 4)
            SelectedDetail(model: model)
            Divider()
            FooterBar(showSettings: $showSettings)
            if showSettings {
                Divider()
                SettingsPanel()
            }
        }
        .frame(width: 340)
        .background(Color(nsColor: .windowBackgroundColor))
        .onReceive(clock.$now) { model.refreshToday($0, tz: settings.timeZone) }
    }
}

// MARK: - 顶部大时间

struct HeaderView: View {
    @EnvironmentObject var clock: Clock
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        let cal = CN.gregorian(settings.timeZone)
        let c = cal.dateComponents([.year, .month, .day, .hour, .minute, .second, .weekday], from: clock.now)
        let weekday = ["周日", "周一", "周二", "周三", "周四", "周五", "周六"][(c.weekday ?? 1) - 1]

        return VStack(spacing: 4) {
            Text(String(format: "%02d:%02d:%02d", c.hour ?? 0, c.minute ?? 0, c.second ?? 0))
                .font(.system(size: 34, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.primary)
            HStack(spacing: 8) {
                Text("\(c.year ?? 0)年\(c.month ?? 0)月\(c.day ?? 0)日")
                Text(weekday)
                    .foregroundStyle(((c.weekday ?? 1) == 1 || (c.weekday ?? 1) == 7) ? .red : .primary)
            }
            .font(.system(size: 13, weight: .medium))
        }
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - 月份导航

struct MonthNavBar: View {
    @EnvironmentObject var settings: AppSettings
    @ObservedObject var model: CalendarModel

    var body: some View {
        let cal = CN.gregorian(settings.timeZone)
        let c = cal.dateComponents([.year, .month], from: model.anchor)
        return HStack {
            navButton("chevron.left") { model.shiftMonth(-1, tz: settings.timeZone) }
            Spacer()
            Text("\(c.year ?? 0) 年 \(c.month ?? 0) 月")
                .font(.system(size: 15, weight: .semibold))
            Button { model.goToday() } label: {
                HStack(spacing: 3) {
                    Image(systemName: "scope").font(.system(size: 9, weight: .bold))
                    Text("今天").font(.system(size: 11, weight: .semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 10).padding(.vertical, 3)
                .background(Color.accentColor)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .padding(.leading, 6)
            Spacer()
            navButton("chevron.right") { model.shiftMonth(1, tz: settings.timeZone) }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    func navButton(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 13, weight: .semibold))
        }
        .buttonStyle(.borderless)
    }
}

// MARK: - 星期表头

struct WeekdayHeader: View {
    let labels = ["日", "一", "二", "三", "四", "五", "六"]
    var body: some View {
        HStack(spacing: 0) {
            ForEach(0..<7, id: \.self) { i in
                Text(labels[i])
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(i == 0 || i == 6 ? .red : .secondary)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 4)
    }
}

// MARK: - 月历网格

struct MonthGrid: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var clock: Clock
    @ObservedObject var model: CalendarModel

    var body: some View {
        let tz = settings.timeZone
        let days = gridDays(anchor: model.anchor, tz: tz)
        let cols = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)
        return LazyVGrid(columns: cols, spacing: 0) {
            ForEach(days) { info in
                DayCellView(
                    info: info,
                    isToday: sameDay(info.date, clock.now, tz),
                    isSelected: sameDay(info.date, model.selected, tz)
                )
                .onTapGesture { model.selected = info.date }
            }
        }
    }

    func gridDays(anchor: Date, tz: TimeZone) -> [DayInfo] {
        let cal = CN.gregorian(tz)
        let comps = cal.dateComponents([.year, .month], from: anchor)
        let displayedMonth = comps.month ?? 1
        guard let first = cal.date(from: DateComponents(year: comps.year, month: comps.month, day: 1)) else { return [] }
        let firstWeekday = cal.component(.weekday, from: first) // 1=周日
        let start = cal.date(byAdding: .day, value: -(firstWeekday - 1), to: first)!
        return (0..<42).compactMap { i in
            guard let d = cal.date(byAdding: .day, value: i, to: start) else { return nil }
            return DayInfoBuilder.build(date: d, displayedMonth: displayedMonth, tz: tz)
        }
    }

    func sameDay(_ a: Date, _ b: Date, _ tz: TimeZone) -> Bool {
        CN.gregorian(tz).isDate(a, inSameDayAs: b)
    }
}

// MARK: - 单元格

struct DayCellView: View {
    let info: DayInfo
    let isToday: Bool
    let isSelected: Bool

    var numberColor: Color {
        if isToday { return .white }
        if !info.isCurrentMonth { return Color.secondary.opacity(0.4) }
        if info.isFestivalDay || info.holiday == .rest { return .red }
        if info.weekday == 1 || info.weekday == 7 { return .red }
        return .primary
    }

    var subColor: Color {
        if isToday { return .white.opacity(0.95) }
        if !info.isCurrentMonth { return Color.secondary.opacity(0.35) }
        if info.isFestivalDay { return .red }
        if info.solarTerm != nil { return .orange }
        return .secondary
    }

    // 角标：调休上班 = 调；法定假日/周末 = 休
    var badge: (String, Color)? {
        if info.holiday == .work { return ("班", .blue) }
        if info.holiday == .rest { return ("休", .green) }
        return nil
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 8)
                .fill(isToday ? Color.orange : (isSelected ? Color.accentColor.opacity(0.16) : Color.clear))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isSelected && !isToday ? Color.accentColor : Color.clear, lineWidth: 1.2)
                )

            VStack(spacing: 1) {
                Text("\(info.solarDay)")
                    .font(.system(size: 16, weight: isToday ? .bold : .regular, design: .rounded))
                    .foregroundStyle(numberColor)
                    .overlay(alignment: .topTrailing) {
                        if info.isCurrentMonth, let b = badge {
                            Text(b.0)
                                .font(.system(size: 8, weight: .semibold))
                                .foregroundStyle(isToday ? .white : b.1)
                                .frame(width: 14, height: 14)
                                .overlay(Circle().stroke(isToday ? Color.white : b.1, lineWidth: 1))
                                .offset(x: 15, y: -5)
                        }
                    }
                Text(info.primaryText)
                    .font(.system(size: 9))
                    .foregroundStyle(subColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
        }
        .frame(height: 46)
        .contentShape(Rectangle())
    }
}

// MARK: - 选中日详情

struct SelectedDetail: View {
    @EnvironmentObject var settings: AppSettings
    @ObservedObject var model: CalendarModel

    var body: some View {
        let tz = settings.timeZone
        let cal = CN.gregorian(tz)
        let info = DayInfoBuilder.build(date: model.selected,
                                        displayedMonth: cal.component(.month, from: model.selected),
                                        tz: tz)
        let lc = CN.lunarCalendar(tz).dateComponents([.year], from: model.selected)
        let weekday = ["周日", "周一", "周二", "周三", "周四", "周五", "周六"][info.weekday - 1]
        let c = cal.dateComponents([.year, .month, .day], from: model.selected)

        return HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(c.year ?? 0)年\(c.month ?? 0)月\(c.day ?? 0)日 \(weekday)")
                    .font(.system(size: 13, weight: .semibold))
                Text("农历\(CN.ganzhiYear(lc.year ?? 1))年〔\(CN.zodiacName(lc.year ?? 1))〕 \(CN.lunarMonths[(info.lunarMonth-1)%12])\(CN.lunarDayName(info.lunarDay))")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                if let f = info.festival { badge(f, .red) }
                if let t = info.solarTerm { badge(t, .orange) }
                if info.holiday == .work {
                    badge("调休上班", .blue)
                } else if info.holiday == .rest {
                    badge("放假", .green)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    func badge(_ text: String, _ color: Color) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .medium))
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }
}

// MARK: - 底部栏

struct FooterBar: View {
    @Binding var showSettings: Bool
    var body: some View {
        HStack {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) { showSettings.toggle() }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "gearshape")
                    Text("设置")
                    Image(systemName: "chevron.up")
                        .font(.system(size: 9, weight: .semibold))
                        .rotationEffect(.degrees(showSettings ? 0 : 180))
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.borderless)
            Spacer()
            Button {
                NSApp.terminate(nil)
            } label: {
                Label("退出", systemImage: "power")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.red)
        }
        .font(.system(size: 12))
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }
}

// MARK: - 设置面板

struct SettingsPanel: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var clock: Clock
    @StateObject private var updater = Updater()
    @State private var launchAtLogin = LoginItem.isEnabled
    @State private var customInput = ""

    /// 选择预置服务器：固定地址，只读
    private func selectPreset(_ host: String) {
        settings.useCustomNTP = false
        settings.ntpServer = host
        clock.setServer(host)
    }
    /// 切到自定义模式：下方显示输入框
    private func enableCustom() {
        settings.useCustomNTP = true
        customInput = AppSettings.ntpServers.contains { $0.0 == settings.ntpServer } ? "" : settings.ntpServer
    }
    /// 应用自定义输入的服务器
    private func applyCustom() {
        let h = customInput.trimmingCharacters(in: .whitespaces)
        guard !h.isEmpty else { return }
        settings.ntpServer = h
        clock.setServer(h)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("时区").font(.system(size: 12, weight: .medium))
                Spacer()
                Picker("", selection: Binding(
                    get: { settings.timeZoneID },
                    set: { settings.timeZoneID = $0 }
                )) {
                    ForEach(AppSettings.commonZones, id: \.0) { z in
                        Text(z.1).tag(z.0)
                    }
                }
                .labelsHidden()
                .frame(width: 150)
            }
            Toggle(isOn: Binding(
                get: { settings.showSeconds },
                set: { settings.showSeconds = $0 }
            )) {
                Text("菜单栏显示秒").font(.system(size: 12))
            }
            .toggleStyle(.switch)
            .controlSize(.small)

            Toggle(isOn: Binding(
                get: { launchAtLogin },
                set: { v in launchAtLogin = v; LoginItem.set(v) }
            )) {
                Text("开机自启动").font(.system(size: 12))
            }
            .toggleStyle(.switch)
            .controlSize(.small)

            Divider()

            // NTP 网络校时
            HStack {
                Text("校时服务器").font(.system(size: 12, weight: .medium))
                Spacer()
                Menu(ntpLabel) {
                    ForEach(AppSettings.ntpServers, id: \.0) { s in
                        Button("\(s.1)  (\(s.0))") { selectPreset(s.0) }
                    }
                    Divider()
                    Button("自定义…") { enableCustom() }
                }
                .frame(width: 150)
            }
            if settings.useCustomNTP {
                // 自定义模式：可输入
                HStack(spacing: 6) {
                    TextField("输入自定义 NTP 服务器", text: $customInput)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 11))
                        .onSubmit { applyCustom() }
                    Button("应用") { applyCustom() }
                        .controlSize(.small)
                        .disabled(customInput.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            } else {
                // 预置模式：只读展示地址
                HStack {
                    Text("地址").font(.system(size: 11)).foregroundStyle(.secondary)
                    Spacer()
                    Text(settings.ntpServer)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }

            HStack(spacing: 8) {
                syncStatusView
                Spacer()
                Button {
                    clock.setServer(settings.ntpServer)
                } label: {
                    Text("立即校时").font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(clock.syncStatus == .syncing)
            }

            Divider()

            HStack(spacing: 8) {
                Text("版本 \(AppInfo.version)").font(.system(size: 12))
                Spacer()
                updateStatusView
                Button {
                    updater.check()
                } label: {
                    Text("检查更新").font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(updater.status == .checking)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .onAppear {
            launchAtLogin = LoginItem.isEnabled
            if settings.useCustomNTP { customInput = settings.ntpServer }
        }
    }

    var ntpLabel: String {
        if settings.useCustomNTP { return "自定义" }
        return AppSettings.ntpServers.first { $0.0 == settings.ntpServer }?.1 ?? settings.ntpServer
    }

    @ViewBuilder
    var syncStatusView: some View {
        switch clock.syncStatus {
        case .idle:
            EmptyView()
        case .syncing:
            HStack(spacing: 4) {
                ProgressView().controlSize(.small).scaleEffect(0.7)
                Text("校时中…").font(.system(size: 11)).foregroundStyle(.secondary)
            }
        case .synced(let off):
            let ms = Int(abs(off) * 1000)
            Text(ms <= 50 ? "已校准 · 误差<50ms"
                          : "已校准 · 本地\(off > 0 ? "慢" : "快")\(ms)ms")
                .font(.system(size: 11)).foregroundStyle(.green)
        case .failed:
            Text("校时失败，检查网络/服务器").font(.system(size: 11)).foregroundStyle(.red)
        }
    }

    @ViewBuilder
    var updateStatusView: some View {
        switch updater.status {
        case .idle:
            EmptyView()
        case .checking:
            ProgressView().controlSize(.small).scaleEffect(0.7)
        case .upToDate:
            Text("已是最新").font(.system(size: 11)).foregroundStyle(.secondary)
        case .available(let v, let url):
            Button {
                NSWorkspace.shared.open(url)
            } label: {
                Text("发现 \(v)，去下载").font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8).padding(.vertical, 2)
                    .background(Color.orange).clipShape(Capsule())
            }
            .buttonStyle(.plain)
        case .failed(let msg):
            Text(msg).font(.system(size: 11)).foregroundStyle(.red)
        }
    }
}
