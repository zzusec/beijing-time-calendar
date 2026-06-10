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

@MainActor
final class Updater: ObservableObject {
    enum Status: Equatable {
        case idle
        case checking
        case upToDate
        case available(version: String, url: URL)
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
