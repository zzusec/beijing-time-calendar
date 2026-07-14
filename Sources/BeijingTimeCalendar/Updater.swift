import SwiftUI
import AppKit

// MARK: - 版本与在线更新

enum AppInfo {
    /// 当前版本号，优先取打包后 Info.plist 的 CFBundleShortVersionString
    static let version: String =
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "1.0"

    static let repo = "zzusec/beijing-time-calendar"
    static let releasesPage = URL(string: "https://github.com/\(repo)/releases/latest")!
}

struct UpgradeFailure: Error, LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

@MainActor
final class Updater: ObservableObject {
    enum Status: Equatable {
        case idle
        case checking
        case upToDate
        case available(version: String, url: URL)
        case upgrading(String)
        case failed(String)
    }

    @Published var status: Status = .idle

    func check() {
        status = .checking
        Task {
            do {
                let (tag, page) = try await Self.fetchLatest()
                let latest = tag.trimmingCharacters(in: CharacterSet(charactersIn: "vV "))
                if Self.isNewer(latest, than: AppInfo.version) {
                    status = .available(version: latest, url: page)
                } else {
                    status = .upToDate
                }
            } catch {
                status = .failed("检查失败，请稍后重试")
            }
        }
    }

    /// 在线升级：下载新版 DMG，替换当前 App 后自动重启。
    func upgrade(version: String, url: URL) {
        guard url.pathExtension == "dmg" else {
            // Release 无 DMG 资产时退回浏览器下载
            NSWorkspace.shared.open(url)
            return
        }
        status = .upgrading("正在下载 v\(version)…")
        Task {
            do {
                let (dmg, response) = try await URLSession.shared.download(from: url)
                guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                    throw UpgradeFailure(message: "下载失败，请稍后重试")
                }
                status = .upgrading("正在安装…")
                let appPath = Bundle.main.bundlePath
                try await Task.detached {
                    try Self.install(dmg: dmg, to: appPath)
                }.value
                Self.relaunch(appPath: appPath)
            } catch {
                status = .failed((error as? LocalizedError)?.errorDescription ?? "升级失败，请稍后重试")
            }
        }
    }

    /// 挂载 DMG，把其中的 App 复制到目标路径；失败时回滚旧版本。
    private nonisolated static func install(dmg: URL, to appPath: String) throws {
        let mountPoint = NSTemporaryDirectory() + "btc-upgrade-\(ProcessInfo.processInfo.processIdentifier)"
        try run("/usr/bin/hdiutil", ["attach", dmg.path, "-nobrowse", "-readonly", "-mountpoint", mountPoint])
        defer { _ = try? run("/usr/bin/hdiutil", ["detach", mountPoint, "-force"]) }

        let fm = FileManager.default
        guard let newApp = try fm.contentsOfDirectory(atPath: mountPoint)
            .first(where: { $0.hasSuffix(".app") })
            .map({ mountPoint + "/" + $0 }) else {
            throw UpgradeFailure(message: "安装包中未找到应用")
        }

        // 暂存目录与目标同级，保证替换是同卷 rename，可原子回滚
        let parent = (appPath as NSString).deletingLastPathComponent
        let staged = parent + "/.btc-update.app"
        let backup = parent + "/.btc-backup.app"
        try? fm.removeItem(atPath: staged)
        try? fm.removeItem(atPath: backup)
        try run("/usr/bin/ditto", ["--noqtn", newApp, staged])

        try fm.moveItem(atPath: appPath, toPath: backup)
        do {
            try fm.moveItem(atPath: staged, toPath: appPath)
        } catch {
            try? fm.moveItem(atPath: backup, toPath: appPath)
            throw UpgradeFailure(message: "替换应用失败，已保留当前版本")
        }
        try? fm.removeItem(atPath: backup)
    }

    /// 等当前进程退出后启动新版本。
    private nonisolated static func relaunch(appPath: String) {
        let pid = ProcessInfo.processInfo.processIdentifier
        let script = "while /bin/kill -0 \(pid) 2>/dev/null; do /bin/sleep 0.2; done; /usr/bin/open \"\(appPath)\""
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", script]
        try? p.run()
        Task { @MainActor in NSApp.terminate(nil) }
    }

    @discardableResult
    private nonisolated static func run(_ tool: String, _ args: [String]) throws -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        let out = Pipe()
        p.standardOutput = out
        p.standardError = out
        try p.run()
        p.waitUntilExit()
        let text = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        guard p.terminationStatus == 0 else {
            NSLog("升级命令失败 \(tool): \(text)")
            throw UpgradeFailure(message: "安装新版本失败")
        }
        return text
    }

    /// 请求 GitHub 最新 Release，返回 (tag_name, 下载/发布页 URL)
    private static func fetchLatest() async throws -> (String, URL) {
        let api = URL(string: "https://api.github.com/repos/\(AppInfo.repo)/releases/latest")!
        var req = URLRequest(url: api)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("BeijingTimeCalendar", forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 12

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let tag = json?["tag_name"] as? String else {
            throw URLError(.cannotParseResponse)
        }
        // 优先 .dmg 直链，否则用 release 页面
        var url = (json?["html_url"] as? String).flatMap(URL.init) ?? AppInfo.releasesPage
        if let assets = json?["assets"] as? [[String: Any]],
           let dmg = assets.first(where: { ($0["name"] as? String)?.hasSuffix(".dmg") == true }),
           let link = (dmg["browser_download_url"] as? String).flatMap(URL.init) {
            url = link
        }
        return (tag, url)
    }

    /// 语义化版本比较：a 是否比 b 新
    static func isNewer(_ a: String, than b: String) -> Bool {
        let pa = a.split(separator: ".").map { Int($0) ?? 0 }
        let pb = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0
            let y = i < pb.count ? pb[i] : 0
            if x != y { return x > y }
        }
        return false
    }
}
