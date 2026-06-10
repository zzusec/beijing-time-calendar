import Foundation

// MARK: - 农历 / 节气 / 节日 / 假日 数据与计算

enum CN {

    // 农历月份名（正月..腊月）
    static let lunarMonths = ["正月", "二月", "三月", "四月", "五月", "六月",
                              "七月", "八月", "九月", "十月", "冬月", "腊月"]

    // 农历日名（初一..三十）
    static let lunarDays = [
        "初一", "初二", "初三", "初四", "初五", "初六", "初七", "初八", "初九", "初十",
        "十一", "十二", "十三", "十四", "十五", "十六", "十七", "十八", "十九", "二十",
        "廿一", "廿二", "廿三", "廿四", "廿五", "廿六", "廿七", "廿八", "廿九", "三十"
    ]

    static let heavenlyStems = ["甲", "乙", "丙", "丁", "戊", "己", "庚", "辛", "壬", "癸"]
    static let earthlyBranches = ["子", "丑", "寅", "卯", "辰", "巳", "午", "未", "申", "酉", "戌", "亥"]
    static let zodiac = ["鼠", "牛", "虎", "兔", "龙", "蛇", "马", "羊", "猴", "鸡", "狗", "猪"]

    // 24 节气名称（从小寒开始）
    static let termNames = ["小寒", "大寒", "立春", "雨水", "惊蛰", "春分", "清明", "谷雨",
                            "立夏", "小满", "芒种", "夏至", "小暑", "大暑", "立秋", "处暑",
                            "白露", "秋分", "寒露", "霜降", "立冬", "小雪", "大雪", "冬至"]

    // 寿星公式常数 C（21 世纪 2000-2099）
    static let termC = [5.4055, 20.12, 3.87, 18.73, 5.63, 20.646, 4.81, 20.1,
                        5.52, 21.04, 5.678, 21.37, 7.108, 22.83, 7.5, 23.13,
                        7.646, 23.042, 8.318, 23.438, 7.438, 22.36, 7.18, 22.6]

    static func lunarCalendar(_ tz: TimeZone) -> Calendar {
        var cal = Calendar(identifier: .chinese)
        cal.timeZone = tz
        return cal
    }

    static func gregorian(_ tz: TimeZone) -> Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        return cal
    }

    // 某节气在某年某月的日期（无则返回 nil）
    static func solarTerm(year: Int, month: Int, day: Int) -> String? {
        let y = Double(year - 2000)
        for k in 0..<2 {
            let i = (month - 1) * 2 + k
            let d = Int(floor(y * 0.2422 + termC[i])) - Int(floor((y - 1) / 4.0))
            if d == day { return termNames[i] }
        }
        return nil
    }

    // 公历固定节日
    static let solarFestivals: [String: String] = [
        "1-1": "元旦", "2-14": "情人节", "3-8": "妇女节", "3-12": "植树节",
        "4-1": "愚人节", "5-1": "劳动节", "5-4": "青年节", "6-1": "儿童节",
        "7-1": "建党节", "8-1": "建军节", "9-10": "教师节", "10-1": "国庆节",
        "12-24": "平安夜", "12-25": "圣诞节"
    ]

    // 农历固定节日
    static let lunarFestivals: [String: String] = [
        "1-1": "春节", "1-15": "元宵", "2-2": "龙抬头", "5-5": "端午",
        "7-7": "七夕", "7-15": "中元", "8-15": "中秋", "9-9": "重阳",
        "12-8": "腊八", "12-23": "小年"
    ]

    static func lunarDayName(_ day: Int) -> String {
        guard day >= 1 && day <= 30 else { return "" }
        return lunarDays[day - 1]
    }

    static func ganzhiYear(_ year: Int) -> String {
        // year: 农历干支序号 1...60
        let i = (year - 1) % 60
        return heavenlyStems[i % 10] + earthlyBranches[i % 12]
    }

    static func zodiacName(_ year: Int) -> String {
        let i = (year - 1) % 12
        return zodiac[i]
    }
}

// MARK: - 单日信息

struct DayInfo: Identifiable {
    // 用日期本身作为稳定 id，避免每秒刷新时 ForEach 全量重建导致 AttributeGraph 崩溃
    var id: TimeInterval { date.timeIntervalSinceReferenceDate }
    let date: Date
    let solarDay: Int
    let isCurrentMonth: Bool
    let weekday: Int          // 1=周日 ... 7=周六
    let lunarMonth: Int
    let lunarDay: Int
    let isLeapMonth: Bool

    let lunarText: String     // 初一显示月名，否则日名
    let solarTerm: String?
    let festival: String?
    let primaryText: String   // 单元格副文本：节日 > 节气 > 农历
    let isFestivalDay: Bool
    let holiday: HolidayKind?
}

enum HolidayKind { case rest, work }   // 休 / 班

enum DayInfoBuilder {

    static func build(date: Date, displayedMonth: Int, tz: TimeZone) -> DayInfo {
        let g = CN.gregorian(tz)
        let l = CN.lunarCalendar(tz)

        let gc = g.dateComponents([.year, .month, .day, .weekday], from: date)
        let lc = l.dateComponents([.year, .month, .day], from: date)
        let isLeap = (l.dateComponents([.month], from: date).isLeapMonth ?? false)

        let sYear = gc.year ?? 2000
        let sMonth = gc.month ?? 1
        let sDay = gc.day ?? 1
        let weekday = gc.weekday ?? 1
        let lMonth = lc.month ?? 1
        let lDay = lc.day ?? 1

        // 农历文本
        var lunarText: String
        if lDay == 1 {
            lunarText = (isLeap ? "闰" : "") + CN.lunarMonths[(lMonth - 1) % 12]
        } else {
            lunarText = CN.lunarDayName(lDay)
        }

        let term = CN.solarTerm(year: sYear, month: sMonth, day: sDay)

        // 节日：除夕特判（次日为正月初一）
        var festival = CN.solarFestivals["\(sMonth)-\(sDay)"]
        if festival == nil {
            festival = CN.lunarFestivals["\(lMonth)-\(lDay)"]
        }
        if festival == nil, let tomorrow = g.date(byAdding: .day, value: 1, to: date) {
            let tlc = l.dateComponents([.month, .day], from: tomorrow)
            if tlc.month == 1 && tlc.day == 1 { festival = "除夕" }
        }
        // 母亲节 / 父亲节 / 感恩节（按周计算）
        if let wf = weekdayFestival(year: sYear, month: sMonth, day: sDay, weekday: weekday) {
            festival = festival ?? wf
        }

        let primary = festival ?? term ?? lunarText
        let holiday = Holidays.kind(year: sYear, month: sMonth, day: sDay)

        return DayInfo(
            date: date,
            solarDay: sDay,
            isCurrentMonth: sMonth == displayedMonth,
            weekday: weekday,
            lunarMonth: lMonth,
            lunarDay: lDay,
            isLeapMonth: isLeap,
            lunarText: lunarText,
            solarTerm: term,
            festival: festival,
            primaryText: primary,
            isFestivalDay: festival != nil,
            holiday: holiday
        )
    }

    // 第 n 个星期几的节日
    static func weekdayFestival(year: Int, month: Int, day: Int, weekday: Int) -> String? {
        let nth = (day - 1) / 7 + 1
        if month == 5 && weekday == 1 && nth == 2 { return "母亲节" }
        if month == 6 && weekday == 1 && nth == 3 { return "父亲节" }
        if month == 11 && weekday == 5 && nth == 4 { return "感恩节" }
        return nil
    }
}

// MARK: - 法定节假日（休/班），可按年补充

enum Holidays {
    // 键："yyyy-M-d"
    static let rest: Set<String> = [
        // 2026 年放假安排（休）
        "2026-1-1",
        "2026-2-15", "2026-2-16", "2026-2-17", "2026-2-18", "2026-2-19", "2026-2-20", "2026-2-21",
        "2026-4-4", "2026-4-5", "2026-4-6",
        "2026-5-1", "2026-5-2", "2026-5-3", "2026-5-4", "2026-5-5",
        "2026-6-19", "2026-6-20", "2026-6-21",
        "2026-9-25", "2026-9-26", "2026-9-27",
        "2026-10-1", "2026-10-2", "2026-10-3", "2026-10-4", "2026-10-5", "2026-10-6", "2026-10-7", "2026-10-8"
    ]
    static let work: Set<String> = [
        // 调休上班（班）
        "2026-2-14", "2026-2-22",
        "2026-9-28", "2026-10-10"
    ]

    static func kind(year: Int, month: Int, day: Int) -> HolidayKind? {
        let key = "\(year)-\(month)-\(day)"
        if rest.contains(key) { return .rest }
        if work.contains(key) { return .work }
        return nil
    }
}
