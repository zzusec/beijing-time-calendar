<div align="center">
  <img src="icon_1024.png" width="128" alt="logo" />
  <h1>北京时间万年历</h1>
  <p>一款常驻 macOS 菜单栏的北京时间万年历 App，专为海外用户随时查看国内时间与农历而生。</p>
</div>

## ✨ 功能

- **菜单栏常驻**：实时显示北京时间 + 星期 + 日期，例如 `周一 6/8 23:45`
- **点击弹出万年历**：
  - 公历 + 农历（初一显示月名，如「五月」）
  - 24 节气（芒种、夏至、小暑…）
  - 传统与公历节日（春节、端午、儿童节、父亲节、除夕…）
  - 法定节假日 **休 / 班** 角标
- **时区切换**：北京、香港、台北、东京、纽约、伦敦等常用时区一键切换
- **一键回今天**、上/下月浏览
- **开机自启动**（基于 `SMAppService` 登录项）
- **菜单栏显示秒** 开关
- **可靠校时**：首选 NTP 不可用时自动切换多个 NTP；UDP/123 均不可达时使用 HTTPS 时间源后备，状态区会显示实际校时来源
- 原生 SwiftUI，精美、轻量（< 1 MB），无 Dock 图标

## 🛠 技术

- 纯原生 **SwiftUI + AppKit**（`MenuBarExtra`），无第三方依赖
- 农历基于系统 `Calendar(.chinese)`
- 24 节气采用「寿星公式」计算（适用 2000–2099）
- 节日含公历固定、农历固定、按周（母亲节/父亲节/感恩节）及除夕特判
- 法定节假日 休/班 为数据表，已内置 2026 全年安排

## 📦 构建运行

需要 macOS 13+ 与 Xcode（含 Swift 5.9+）。

```bash
git clone https://github.com/zzusec/beijing-time-calendar.git
cd beijing-time-calendar
./build_app.sh           # 编译并打包为「北京时间万年历.app」
open 北京时间万年历.app    # 运行
```

把生成的 `北京时间万年历.app` 拖到「应用程序」即可正式安装，并在 App 内开启「开机自启动」。

重新生成图标（可选）：

```bash
swift make_icon.swift    # 生成 icon_1024.png
# 再用 iconutil 转 Resources/AppIcon.icns
```

## 🗓 维护假日数据

休/班 调休安排每年由国务院公布，无法自动计算。新年份需在
[`Sources/BeijingTimeCalendar/ChineseCalendar.swift`](Sources/BeijingTimeCalendar/ChineseCalendar.swift)
的 `Holidays.rest` / `Holidays.work` 集合中按 `"yyyy-M-d"` 补充即可。农历、节气、节日均为自动计算，无需维护。

## 📄 许可

[MIT](LICENSE)
