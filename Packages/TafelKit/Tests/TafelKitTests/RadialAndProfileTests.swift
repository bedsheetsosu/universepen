import XCTest
@testable import TafelKit

final class RadialAndProfileTests: XCTestCase {
    func testRadialItemUnderPoint() {
        let r = RadialMenuLayout.radius
        XCTAssertEqual(RadialMenuLayout.item(dx: 0, dy: -r, count: 6), 0)      // top
        XCTAssertEqual(RadialMenuLayout.item(dx: r, dy: 0, count: 4), 1)       // right
        XCTAssertEqual(RadialMenuLayout.item(dx: 0, dy: r, count: 4), 2)       // bottom
        XCTAssertEqual(RadialMenuLayout.item(dx: -r, dy: 0, count: 4), 3)      // left
        XCTAssertEqual(RadialMenuLayout.item(dx: -5, dy: -r, count: 6), 0)     // just left of top wraps to 0
        XCTAssertNil(RadialMenuLayout.item(dx: 5, dy: 5, count: 6))            // dead zone
        XCTAssertNil(RadialMenuLayout.item(dx: 500, dy: 0, count: 6))          // far outside
    }

    func testItemCentresMapBackToTheirItem() {
        for n in 2...8 {
            for i in 0..<n {
                let o = RadialMenuLayout.offset(of: i, count: n)
                XCTAssertEqual(RadialMenuLayout.item(dx: o.x, dy: o.y, count: n), i, "n=\(n) i=\(i)")
            }
        }
    }

    func testPerAppProfileOverridesOnlyPencilPart() {
        var s = InputSettings()
        var p = s.penProfile
        p.squeeze = .radialMenu
        p.positionSmoothing = 0.7
        s.appPenProfiles["com.seriflabs.affinity"] = p
        let e = s.effective(for: "com.seriflabs.affinity")
        XCTAssertEqual(e.squeeze, .radialMenu)
        XCTAssertEqual(e.positionSmoothing, 0.7)
        XCTAssertEqual(e.zoomMethod, s.zoomMethod)
        XCTAssertEqual(s.effective(for: "com.other"), s)
        XCTAssertEqual(s.effective(for: nil), s)
    }

    func testOldSettingsDecodeAndNewOnesRoundTrip() throws {
        let old = try JSONDecoder().decode(InputSettings.self, from: Data(#"{"squeeze":{"shortcut":{"_0":{"key":"z","modifiers":1}}}}"#.utf8))
        XCTAssertEqual(old.radialMenu.count, InputSettings.defaultRadialMenu.count)
        var s = InputSettings()
        s.squeeze = .radialMenu
        s.appPenProfiles["x"] = s.penProfile
        XCTAssertEqual(try JSONDecoder().decode(InputSettings.self, from: JSONEncoder().encode(s)), s)
    }

    func testClientConfigBatteryRoundTrip() throws {
        let c = ClientConfig(viewPixelWidth: 1, viewPixelHeight: 1, quality: StreamQuality(), batteryLevel: 0.42, batteryCharging: true)
        XCTAssertEqual(try JSONWire.decode(ClientConfig.self, JSONWire.encode(c)), c)
    }
}

final class GameModeAndSourceTests: XCTestCase {
    func testGameAppDropsSmoothingAndRaisesQuality() {
        var s = InputSettings()
        s.positionSmoothing = 0.5
        s.gameApps["sh.ppy.osu.lazer"] = "osu!"
        XCTAssertEqual(s.effective(for: "sh.ppy.osu.lazer").positionSmoothing, 0)
        XCTAssertEqual(s.effective(for: "sh.ppy.osu.lazer").pressureSmoothing, 0)
        XCTAssertEqual(s.effective(for: "com.other").positionSmoothing, 0.5)
        let q = StreamQuality(fps: 30, resolutionScale: 0.5, adaptive: true, fullSource: false).gameMode
        XCTAssertEqual(q.fps, 60); XCTAssertEqual(q.resolutionScale, 1)
        XCTAssertTrue(q.fullSource); XCTAssertFalse(q.adaptive); XCTAssertGreaterThanOrEqual(q.bitrateMbps, 60)
    }

    func testSourceMessagesRoundTrip() throws {
        let l = SourceList(mode: "window", modes: [SourceOption(id: "display", title: "Display")],
                           displays: [SourceOption(id: "1", title: "Built-in")], selectedDisplay: "1",
                           windows: [SourceOption(id: "42", title: "Affinity – x")], selectedWindow: "42")
        XCTAssertEqual(try JSONWire.decode(SourceList.self, JSONWire.encode(l)), l)
        let sel = SourceSelection(mode: "window", window: "42")
        XCTAssertEqual(try JSONWire.decode(SourceSelection.self, JSONWire.encode(sel)), sel)
    }
}

final class TabletAreaTests: XCTestCase {
    func testLockKeepsAspectInsideAndCentre() {
        let size = CGSize(width: 1180, height: 820)
        let a = TabletArea(x: 0.1, y: 0.1, width: 0.5, height: 0.5).locked(to: 1710.0 / 1112.0, in: size)
        let r = a.rect(in: size)
        XCTAssertEqual(Double(r.width / r.height), 1710.0 / 1112.0, accuracy: 0.001)
        XCTAssertGreaterThanOrEqual(r.minX, 0); XCTAssertLessThanOrEqual(r.maxX, size.width + 0.001)
        XCTAssertGreaterThanOrEqual(r.minY, 0); XCTAssertLessThanOrEqual(r.maxY, size.height + 0.001)
        XCTAssertEqual(Double(r.midX), 0.35 * 1180, accuracy: 0.5)
    }

    func testHugeAreaIsClampedToTheView() {
        let size = CGSize(width: 1180, height: 820)
        let r = TabletArea(x: 0, y: 0, width: 1, height: 1).locked(to: 16.0 / 9.0, in: size).rect(in: size)
        XCTAssertLessThanOrEqual(r.width, size.width + 0.001)
        XCTAssertLessThanOrEqual(r.height, size.height + 0.001)
    }

    func testTabletModeRestartsStream() {
        let a = ClientConfig(viewPixelWidth: 10, viewPixelHeight: 10, quality: StreamQuality())
        var b = a; b.tabletMode = true
        XCTAssertFalse(b.sameStream(as: a))
    }
}
