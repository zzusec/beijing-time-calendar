import Foundation

struct TimeSyncResult: Equatable, Sendable {
    let offset: TimeInterval
    let source: TimeSyncSource
}

enum TimeSyncSource: Equatable, Sendable {
    case ntp(host: String)
    case https(provider: String)

    var statusText: String {
        switch self {
        case .ntp(let host):
            return "NTP · \(host)"
        case .https(let provider):
            return "HTTPS 备用 · \(provider)"
        }
    }
}

struct TimeSyncFailure: Error, Equatable, LocalizedError, Sendable {
    let message: String

    var errorDescription: String? { message }
}

/// 协调多层校时策略：优先 NTP，UDP/123 全部不可用时再使用 HTTPS 时间源。
struct TimeSyncService: Sendable {
    typealias NTPQuery = @Sendable (_ host: String, _ timeoutSeconds: Double) async throws -> TimeInterval
    typealias HTTPSQuery = @Sendable () async throws -> TimeSyncResult

    private static let fallbackNTPHosts = [
        "ntp.aliyun.com",
        "ntp.ntsc.ac.cn",
        "cn.pool.ntp.org",
        "time.cloudflare.com",
        "time.apple.com"
    ]

    private let ntpQuery: NTPQuery
    private let httpsQuery: HTTPSQuery

    init(
        ntpQuery: @escaping NTPQuery = { host, timeoutSeconds in
            try await NTPClient.offset(host: host, timeoutSeconds: timeoutSeconds)
        },
        httpsQuery: @escaping HTTPSQuery = {
            try await HTTPSDateClient.fetchFallback()
        }
    ) {
        self.ntpQuery = ntpQuery
        self.httpsQuery = httpsQuery
    }

    func synchronize(preferredHost: String) async throws -> TimeSyncResult {
        let hosts = ntpCandidates(preferredHost: preferredHost)
        var ntpErrors: [String] = []

        for host in hosts {
            try Task.checkCancellation()
            do {
                let offset = try await ntpQuery(host, 2.5)
                return TimeSyncResult(offset: offset, source: .ntp(host: host))
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                ntpErrors.append("\(host): \(error.localizedDescription)")
            }
        }

        do {
            return try await httpsQuery()
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            NSLog("校时失败。NTP: \(ntpErrors.joined(separator: " | ")); HTTPS: \(error.localizedDescription)")
            throw TimeSyncFailure(message: "UDP/123 与 HTTPS 备用均不可用")
        }
    }

    func ntpCandidates(preferredHost: String) -> [String] {
        var seen = Set<String>()
        let hosts = [preferredHost] + Self.fallbackNTPHosts
        return hosts.compactMap { raw in
            let host = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !host.isEmpty else { return nil }
            guard seen.insert(host.lowercased()).inserted else { return nil }
            return host
        }.prefix(4).map { $0 }
    }
}

/// HTTPS 备用时间源。仅在 NTP 全部失败时调用，优先保证可用性而非 NTP 级精度。
enum HTTPSDateClient {
    private static let timeout: TimeInterval = 5

    static func fetchFallback() async throws -> TimeSyncResult {
        let providers: [(String, URL, (Data) throws -> TimeInterval)] = [
            ("Cloudflare", URL(string: "https://www.cloudflare.com/cdn-cgi/trace")!, parseCloudflareTrace),
            ("TimeAPI", URL(string: "https://timeapi.io/api/time/current/zone?timeZone=Asia%2FShanghai")!, parseTimeAPI)
        ]
        var failures: [String] = []

        for (name, url, parse) in providers {
            try Task.checkCancellation()
            do {
                let offset = try await offset(url: url, parser: parse)
                return TimeSyncResult(offset: offset, source: .https(provider: name))
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                failures.append("\(name): \(error.localizedDescription)")
            }
        }

        throw TimeSyncFailure(message: "HTTPS 备用时间服务无响应：\(failures.joined(separator: "；"))")
    }

    static func offset(url: URL, parser: (Data) throws -> TimeInterval) async throws -> TimeInterval {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeout)
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        let startedAt = Date().timeIntervalSince1970
        let (data, response) = try await URLSession.shared.data(for: request)
        let receivedAt = Date().timeIntervalSince1970
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw TimeSyncFailure(message: "HTTPS 服务响应异常")
        }
        let serverTime = try parser(data)
        return serverTime - (startedAt + receivedAt) / 2
    }

    static func parseCloudflareTrace(_ data: Data) throws -> TimeInterval {
        guard let text = String(data: data, encoding: .utf8) else {
            throw TimeSyncFailure(message: "Cloudflare 时间数据无效")
        }
        for line in text.split(separator: "\n") {
            let parts = line.split(separator: "=", maxSplits: 1)
            if parts.count == 2, parts[0] == "ts", let timestamp = TimeInterval(parts[1]) {
                return timestamp
            }
        }
        throw TimeSyncFailure(message: "Cloudflare 时间数据缺失")
    }

    static func parseTimeAPI(_ data: Data) throws -> TimeInterval {
        struct Response: Decodable {
            let year: Int
            let month: Int
            let day: Int
            let hour: Int
            let minute: Int
            let seconds: Int
            let milliSeconds: Int
        }
        do {
            let response = try JSONDecoder().decode(Response.self, from: data)
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
            var components = DateComponents()
            components.year = response.year
            components.month = response.month
            components.day = response.day
            components.hour = response.hour
            components.minute = response.minute
            components.second = response.seconds
            components.nanosecond = response.milliSeconds * 1_000_000
            guard let date = calendar.date(from: components) else {
                throw TimeSyncFailure(message: "TimeAPI 时间数据无效")
            }
            return date.timeIntervalSince1970
        } catch let error as TimeSyncFailure {
            throw error
        } catch {
            throw TimeSyncFailure(message: "TimeAPI 时间数据无效")
        }
    }
}
