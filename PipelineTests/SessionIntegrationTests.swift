import XCTest
import Network
import TafelKit

/// Real HostServer + real client Session/PairingAttempt over 127.0.0.1 (no Bonjour, no capture,
/// no injected events: callbacks are captured instead of posted).
final class SessionIntegrationTests: XCTestCase {
    private func waitForPort(_ get: @escaping () -> UInt16?) -> UInt16? {
        for _ in 0..<100 {
            if let p = get(), p != 0 { return p }
            Thread.sleep(forTimeInterval: 0.05)
        }
        return nil
    }

    func testPairThenStreamAndInput() throws {
        let server = HostServer()
        server.hostID = "HOST-1"
        server.hostName = "Test-Mac"
        server.advertise = false
        let hostKey = HostKey.generate()
        server.start(key: hostKey)
        let code = PairingCode.generate()
        server.startPairing(code: code, hostKey: hostKey)
        let pairPort = try XCTUnwrap(waitForPort { server.pairingPort })
        let mainPort = try XCTUnwrap(waitForPort { server.mainPort })

        // 1. Wrong code is rejected.
        let rejected = expectation(description: "wrong code rejected")
        PairingAttempt().run(endpoint: .hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: pairPort)!),
                             code: PairingCode.generate(), deviceID: "PAD", deviceName: "Test-iPad") { r in
            if case .failure = r { rejected.fulfill() }
        }
        wait(for: [rejected], timeout: 12)

        // 2. Correct code yields the host key.
        let paired = expectation(description: "paired")
        var grant: PairGrant?
        PairingAttempt().run(endpoint: .hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: pairPort)!),
                             code: code, deviceID: "PAD", deviceName: "Test-iPad") { r in
            if case .success(let g) = r { grant = g; paired.fulfill() }
        }
        wait(for: [paired], timeout: 12)
        XCTAssertEqual(grant?.hostID, "HOST-1")
        let key = try XCTUnwrap(grant.flatMap { Data(base64Encoded: $0.keyBase64) })
        XCTAssertEqual(key, hostKey)

        // 3. Session with the granted key: hostInfo, config, pen, shortcut, video.
        let gotConfig = expectation(description: "config")
        let gotPen = expectation(description: "pen")
        let gotShortcut = expectation(description: "shortcut")
        let gotVideo = expectation(description: "video connection")
        server.onClientConfig = { c in if c.viewPixelWidth == 2360 { gotConfig.fulfill() } }
        server.onPen = { s in if s.phase == .down && abs(s.pressure - 0.5) < 0.001 { gotPen.fulfill() } }
        server.onShortcut = { s in if s == Shortcut("z", .command) { gotShortcut.fulfill() } }
        server.onVideoConnected = { gotVideo.fulfill() }

        let renderer = VideoRenderer()
        let session = Session(endpoint: .hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: mainPort)!),
                              key: key, deviceID: "PAD", deviceName: "Test-iPad", renderer: renderer)
        let connected = expectation(description: "connected")
        session.onConnected = { connected.fulfill() }
        session.start()
        session.send(config: ClientConfig(viewPixelWidth: 2360, viewPixelHeight: 1640, quality: StreamQuality()))
        wait(for: [connected, gotConfig, gotVideo], timeout: 10)
        session.send(PenSample(phase: .down, x: 0.5, y: 0.5, pressure: 0.5))
        session.send(Shortcut("z", .command))
        wait(for: [gotPen, gotShortcut], timeout: 5)

        // 4. Timing reports arrive (ping/pong).
        let timed = expectation(description: "timing")
        timed.assertForOverFulfill = false
        session.onTiming = { t in if t.rttMs > 0 { timed.fulfill() } }
        wait(for: [timed], timeout: 5)

        session.close()
    }

    func testSessionWithWrongKeyFails() throws {
        let server = HostServer()
        server.advertise = false
        server.start(key: HostKey.generate())
        let port = try XCTUnwrap(waitForPort { server.mainPort })
        let session = Session(endpoint: .hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!),
                              key: HostKey.generate(), deviceID: "X", deviceName: "X", renderer: VideoRenderer())
        let failed = expectation(description: "failed")
        session.onConnected = { XCTFail("must not connect") }
        session.onClosed = { reason in if reason != nil { failed.fulfill() } }
        session.start()
        wait(for: [failed], timeout: 12)
    }
}
