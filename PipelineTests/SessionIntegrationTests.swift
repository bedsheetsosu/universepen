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

    /// A second iPad (other device ID) becomes an input-only tablet: it is told so, gets no video,
    /// and its Pencil arrives on the extra-tablet path while the first iPad stays connected.
    func testSecondIPadBecomesTablet() throws {
        let key = HostKey.generate()
        let server = HostServer()
        server.advertise = false
        server.start(key: key)
        let port = try XCTUnwrap(waitForPort { server.mainPort })
        let endpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!)

        let first = Session(endpoint: endpoint, key: key, deviceID: "PAD-A", deviceName: "A", renderer: VideoRenderer())
        let firstUp = expectation(description: "first connected")
        first.onConnected = { firstUp.fulfill() }
        first.start()
        wait(for: [firstUp], timeout: 10)

        let extraPen = expectation(description: "extra pen")
        let names = expectation(description: "extras listed")
        server.onExtraPen = { s in if s.phase == .down { extraPen.fulfill() } }
        server.onPen = { _ in XCTFail("the extra iPad's Pencil must not use the main path") }
        server.onExtrasChanged = { n in if n == ["B"] { names.fulfill() } }

        let second = Session(endpoint: endpoint, key: key, deviceID: "PAD-B", deviceName: "B", renderer: VideoRenderer())
        let secondInfo = expectation(description: "second told it is secondary")
        second.onHostInfo = { info in if info.secondary == true { secondInfo.fulfill() } }
        second.onConnected = { second.send(PenSample(phase: .down, x: 0.5, y: 0.5, pressure: 0.4)) }
        var firstClosed = false
        first.onClosed = { _ in firstClosed = true }
        second.start()
        wait(for: [secondInfo, extraPen, names], timeout: 10)
        XCTAssertFalse(firstClosed, "the first iPad must stay connected")
        second.close()
        first.close()
    }

    func testClipboardBothWays() throws {
        let key = HostKey.generate()
        let server = HostServer()
        server.advertise = false
        server.start(key: key)
        let port = try XCTUnwrap(waitForPort { server.mainPort })
        let endpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!)

        let toMac = expectation(description: "iPad clipboard reached the Mac")
        server.onClipboard = { item in if item.text == "vom iPad ✏️" { toMac.fulfill() } }
        server.clipboardProvider = { .text("vom Mac 🖥") }

        let pad = Session(endpoint: endpoint, key: key, deviceID: "PAD-C", deviceName: "C", renderer: VideoRenderer())
        let fromMac = expectation(description: "Mac clipboard reached the iPad")
        pad.onClipboard = { item in if item.text == "vom Mac 🖥" { fromMac.fulfill() } }
        pad.onConnected = {
            pad.send(clipboard: .text("vom iPad ✏️"))
            pad.requestClipboard()
        }
        pad.start()
        wait(for: [toMac, fromMac], timeout: 10)
        pad.close()
    }

    func testScreenshotRequestReachesIPad() throws {
        let key = HostKey.generate()
        let server = HostServer()
        server.advertise = false
        server.start(key: key)
        let port = try XCTUnwrap(waitForPort { server.mainPort })
        let endpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!)
        let fake = Data(repeating: 0xAB, count: 3 * 1024 * 1024)   // a big image must arrive whole
        server.screenshotProvider = { done in DispatchQueue.global().async { done(fake) } }

        let pad = Session(endpoint: endpoint, key: key, deviceID: "PAD-D", deviceName: "D", renderer: VideoRenderer())
        let got = expectation(description: "screenshot arrived")
        pad.onScreenshot = { d in if d == fake { got.fulfill() } }
        pad.onConnected = { pad.requestScreenshot() }
        pad.start()
        wait(for: [got], timeout: 10)
        pad.close()
    }
}
