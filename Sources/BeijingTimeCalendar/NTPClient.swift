import Foundation
import Network

enum NTPError: Error, Equatable, LocalizedError {
    case timeout
    case invalidResponse(String)
    case network(String)

    var errorDescription: String? {
        switch self {
        case .timeout:
            return "服务器无响应"
        case .invalidResponse:
            return "服务器返回无效时间数据"
        case .network:
            return "网络不可用"
        }
    }
}

/// 轻量 SNTP 客户端：向单个 NTP 服务器查询真实时间，返回本地时钟需叠加的偏移。
/// 真实时间 = 本地时间 + offset
/// 多服务器切换与 HTTPS 后备由 TimeSyncService 负责。
enum NTPClient {
    private static let epochDelta = 2_208_988_800.0 // 1900 -> 1970 的秒数

    static func offset(host: String, timeoutSeconds: Double = 5) async throws -> TimeInterval {
        let conn = NWConnection(host: NWEndpoint.Host(host), port: 123, using: .udp)
        return try await withTaskCancellationHandler(operation: {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { cont in
                let queue = DispatchQueue(label: "ntp.query")
                let lock = NSLock()
                var done = false
                func finish(_ result: Result<TimeInterval, Error>) {
                    lock.lock()
                    defer { lock.unlock() }
                    guard !done else { return }
                    done = true
                    conn.cancel()
                    cont.resume(with: result)
                }

                queue.asyncAfter(deadline: .now() + timeoutSeconds) {
                    finish(.failure(NTPError.timeout))
                }

                conn.stateUpdateHandler = { state in
                    switch state {
                    case .ready:
                        let sentAt = Date().timeIntervalSince1970
                        let packet = makeRequestPacket(at: sentAt)
                        conn.send(content: packet, completion: .contentProcessed { error in
                            if let error {
                                finish(.failure(NTPError.network(error.localizedDescription)))
                                return
                            }
                            conn.receiveMessage { data, _, _, error in
                                let receivedAt = Date().timeIntervalSince1970
                                if let error {
                                    finish(.failure(NTPError.network(error.localizedDescription)))
                                    return
                                }
                                do {
                                    guard let data else {
                                        throw NTPError.invalidResponse("空响应")
                                    }
                                    let result = try offset(
                                        response: data,
                                        requestPacket: packet,
                                        sentAt: sentAt,
                                        receivedAt: receivedAt
                                    )
                                    finish(.success(result))
                                } catch {
                                    finish(.failure(error))
                                }
                            }
                        })
                    case .failed(let error):
                        finish(.failure(NTPError.network(error.localizedDescription)))
                    case .cancelled:
                        finish(.failure(CancellationError()))
                    default:
                        break
                    }
                }
                conn.start(queue: queue)
            }
        }, onCancel: {
            conn.cancel()
        })
    }

    static func makeRequestPacket(at unixTime: TimeInterval) -> Data {
        var packet = [UInt8](repeating: 0, count: 48)
        packet[0] = 0x23 // LI=0, VN=4, Mode=3(client)
        writeTimestamp(unixTime, to: &packet, at: 40)
        return Data(packet)
    }

    static func offset(
        response: Data,
        requestPacket: Data,
        sentAt: TimeInterval,
        receivedAt: TimeInterval
    ) throws -> TimeInterval {
        guard response.count >= 48, requestPacket.count >= 48 else {
            throw NTPError.invalidResponse("数据包长度不足")
        }
        let bytes = [UInt8](response)
        let request = [UInt8](requestPacket)
        let mode = bytes[0] & 0x07
        guard mode == 4 else {
            throw NTPError.invalidResponse("响应模式错误")
        }
        guard (1...15).contains(Int(bytes[1])) else {
            throw NTPError.invalidResponse("stratum 无效")
        }
        guard Array(bytes[24..<32]) == Array(request[40..<48]) else {
            throw NTPError.invalidResponse("originate timestamp 不匹配")
        }
        guard !bytes[32..<40].allSatisfy({ $0 == 0 }), !bytes[40..<48].allSatisfy({ $0 == 0 }) else {
            throw NTPError.invalidResponse("服务器时间戳为空")
        }

        let receivedByServer = readTimestamp(bytes, at: 32)
        let sentByServer = readTimestamp(bytes, at: 40)
        guard receivedByServer.isFinite, sentByServer.isFinite else {
            throw NTPError.invalidResponse("服务器时间戳无效")
        }
        // 标准 NTP 偏移：((T2-T1)+(T3-T4))/2
        return ((receivedByServer - sentAt) + (sentByServer - receivedAt)) / 2
    }

    static func writeTimestamp(_ unix: TimeInterval, to buffer: inout [UInt8], at index: Int) {
        let ntp = unix + epochDelta
        let seconds = UInt32(ntp)
        let fraction = UInt32((ntp - Double(seconds)) * 4_294_967_296.0)
        buffer[index] = UInt8(seconds >> 24 & 0xff)
        buffer[index + 1] = UInt8(seconds >> 16 & 0xff)
        buffer[index + 2] = UInt8(seconds >> 8 & 0xff)
        buffer[index + 3] = UInt8(seconds & 0xff)
        buffer[index + 4] = UInt8(fraction >> 24 & 0xff)
        buffer[index + 5] = UInt8(fraction >> 16 & 0xff)
        buffer[index + 6] = UInt8(fraction >> 8 & 0xff)
        buffer[index + 7] = UInt8(fraction & 0xff)
    }

    static func readTimestamp(_ buffer: [UInt8], at index: Int) -> TimeInterval {
        let seconds = (UInt32(buffer[index]) << 24) | (UInt32(buffer[index + 1]) << 16)
            | (UInt32(buffer[index + 2]) << 8) | UInt32(buffer[index + 3])
        let fraction = (UInt32(buffer[index + 4]) << 24) | (UInt32(buffer[index + 5]) << 16)
            | (UInt32(buffer[index + 6]) << 8) | UInt32(buffer[index + 7])
        return Double(seconds) - epochDelta + Double(fraction) / 4_294_967_296.0
    }
}
