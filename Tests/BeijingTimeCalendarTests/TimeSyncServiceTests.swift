import XCTest
@testable import BeijingTimeCalendar

final class TimeSyncServiceTests: XCTestCase {
    func testCandidatesKeepPreferredHostAndRemoveDuplicates() {
        let service = TimeSyncService()
        let hosts = service.ntpCandidates(preferredHost: "NTP.ALIYUN.COM")

        XCTAssertEqual(hosts.first, "NTP.ALIYUN.COM")
        XCTAssertEqual(hosts.count, 4)
        XCTAssertEqual(hosts.filter { $0.lowercased() == "ntp.aliyun.com" }.count, 1)
    }

    func testFallsBackToNextNTPHostBeforeHTTPS() async throws {
        let calls = CallRecorder()
        let service = TimeSyncService(
            ntpQuery: { host, _ in
                await calls.append(host)
                if host == "preferred.example" { throw NTPError.timeout }
                return 0.125
            },
            httpsQuery: {
                await calls.append("https")
                return TimeSyncResult(offset: 1, source: .https(provider: "test"))
            }
        )

        let result = try await service.synchronize(preferredHost: "preferred.example")

        let recorded = await calls.values()
        XCTAssertEqual(result, TimeSyncResult(offset: 0.125, source: .ntp(host: "ntp.aliyun.com")))
        XCTAssertEqual(recorded, ["preferred.example", "ntp.aliyun.com"])
    }

    func testUsesHTTPSOnlyAfterAllNTPHostsFail() async throws {
        let calls = CallRecorder()
        let service = TimeSyncService(
            ntpQuery: { host, _ in
                await calls.append(host)
                throw NTPError.timeout
            },
            httpsQuery: {
                await calls.append("https")
                return TimeSyncResult(offset: 0.25, source: .https(provider: "test"))
            }
        )

        let result = try await service.synchronize(preferredHost: "preferred.example")

        let recorded = await calls.values()
        XCTAssertEqual(result.source, .https(provider: "test"))
        XCTAssertEqual(recorded.last, "https")
        XCTAssertEqual(recorded.count, 5)
    }

    func testParsesHTTPSFallbackPayloads() throws {
        let cloudflare = try HTTPSDateClient.parseCloudflareTrace(Data("fl=abc\nts=1720000000.125\n".utf8))
        let timeAPI = try HTTPSDateClient.parseTimeAPI(Data("{\"year\":2024,\"month\":7,\"day\":3,\"hour\":17,\"minute\":46,\"seconds\":41,\"milliSeconds\":250}".utf8))

        XCTAssertEqual(cloudflare, 1_720_000_000.125, accuracy: 0.0001)
        XCTAssertEqual(timeAPI, 1_720_000_001.25, accuracy: 0.0001)
    }

    func testValidatesNTPResponseAndCalculatesOffset() throws {
        let sentAt: TimeInterval = 1_720_000_000
        let receivedAt: TimeInterval = sentAt + 0.100
        let request = NTPClient.makeRequestPacket(at: sentAt)
        let requestBytes = [UInt8](request)
        var response = [UInt8](repeating: 0, count: 48)
        response[0] = 0x24 // VN=4, server mode
        response[1] = 1
        response.replaceSubrange(24..<32, with: requestBytes[40..<48])
        NTPClient.writeTimestamp(sentAt + 0.020, to: &response, at: 32)
        NTPClient.writeTimestamp(sentAt + 0.030, to: &response, at: 40)

        let offset = try NTPClient.offset(
            response: Data(response),
            requestPacket: request,
            sentAt: sentAt,
            receivedAt: receivedAt
        )

        XCTAssertEqual(offset, -0.025, accuracy: 0.001)
    }

    @MainActor
    func testVersionComparisonTreatsOneTenAsNewerThanOneNine() {
        XCTAssertTrue(Updater.isNewer("1.10", than: "1.9"))
        XCTAssertFalse(Updater.isNewer("1.9", than: "1.10"))
        XCTAssertFalse(Updater.isNewer("1.10", than: "1.10"))
        XCTAssertTrue(Updater.isNewer("2.0", than: "1.10"))
    }

    func testRejectsNTPResponseWithMismatchedOriginTimestamp() {
        let request = NTPClient.makeRequestPacket(at: 1_720_000_000)
        var response = [UInt8](repeating: 0, count: 48)
        response[0] = 0x24
        response[1] = 1
        NTPClient.writeTimestamp(1_720_000_001, to: &response, at: 32)
        NTPClient.writeTimestamp(1_720_000_002, to: &response, at: 40)

        XCTAssertThrowsError(try NTPClient.offset(
            response: Data(response),
            requestPacket: request,
            sentAt: 1_720_000_000,
            receivedAt: 1_720_000_000.1
        ))
    }
}

private actor CallRecorder {
    private var entries: [String] = []

    func append(_ value: String) {
        entries.append(value)
    }

    func values() -> [String] {
        entries
    }
}
