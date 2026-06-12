import Foundation
import Network

enum NTPError: Error { case timeout, badResponse }

/// 轻量 SNTP 客户端：向 NTP 服务器查询真实时间，返回本地时钟需叠加的偏移。
/// 真实时间 = 本地时间 + offset
enum NTPClient {
    private static let epochDelta = 2208988800.0 // 1900 -> 1970 的秒数

    static func offset(host: String, timeoutSeconds: Double = 5) async throws -> TimeInterval {
        try await withCheckedThrowingContinuation { cont in
            let conn = NWConnection(host: NWEndpoint.Host(host), port: 123, using: .udp)
            let queue = DispatchQueue(label: "ntp.query")
            let lock = NSLock()
            var done = false
            func finish(_ r: Result<TimeInterval, Error>) {
                lock.lock(); defer { lock.unlock() }
                if done { return }
                done = true
                conn.cancel()
                cont.resume(with: r)
            }
            queue.asyncAfter(deadline: .now() + timeoutSeconds) { finish(.failure(NTPError.timeout)) }

            conn.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    var packet = [UInt8](repeating: 0, count: 48)
                    packet[0] = 0x1B // LI=0, VN=3, Mode=3(client)
                    let t1 = Date().timeIntervalSince1970
                    writeTS(t1, &packet, 40)
                    conn.send(content: Data(packet), completion: .contentProcessed { err in
                        if let err = err { finish(.failure(err)); return }
                        conn.receiveMessage { data, _, _, recvErr in
                            let t4 = Date().timeIntervalSince1970
                            if let recvErr = recvErr { finish(.failure(recvErr)); return }
                            guard let data = data, data.count >= 48 else {
                                finish(.failure(NTPError.badResponse)); return
                            }
                            let b = [UInt8](data)
                            let t2 = readTS(b, 32) // 服务器接收时刻
                            let t3 = readTS(b, 40) // 服务器发送时刻
                            // 标准 NTP 偏移：((T2-T1)+(T3-T4))/2
                            finish(.success(((t2 - t1) + (t3 - t4)) / 2))
                        }
                    })
                case .failed(let e):
                    finish(.failure(e))
                default:
                    break
                }
            }
            conn.start(queue: queue)
        }
    }

    private static func writeTS(_ unix: Double, _ buf: inout [UInt8], _ i: Int) {
        let ntp = unix + epochDelta
        let secs = UInt32(ntp)
        let frac = UInt32((ntp - Double(secs)) * 4294967296.0)
        buf[i] = UInt8(secs >> 24 & 0xff); buf[i+1] = UInt8(secs >> 16 & 0xff)
        buf[i+2] = UInt8(secs >> 8 & 0xff); buf[i+3] = UInt8(secs & 0xff)
        buf[i+4] = UInt8(frac >> 24 & 0xff); buf[i+5] = UInt8(frac >> 16 & 0xff)
        buf[i+6] = UInt8(frac >> 8 & 0xff); buf[i+7] = UInt8(frac & 0xff)
    }

    private static func readTS(_ buf: [UInt8], _ i: Int) -> Double {
        let secs = (UInt32(buf[i]) << 24) | (UInt32(buf[i+1]) << 16) | (UInt32(buf[i+2]) << 8) | UInt32(buf[i+3])
        let frac = (UInt32(buf[i+4]) << 24) | (UInt32(buf[i+5]) << 16) | (UInt32(buf[i+6]) << 8) | UInt32(buf[i+7])
        return Double(secs) - epochDelta + Double(frac) / 4294967296.0
    }
}
