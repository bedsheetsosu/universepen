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

    func testAppBoundPresetWinsWhileAppInFront() {
        var s = InputSettings()
        s.tabletArea = TabletArea(x: 0, y: 0, width: 1, height: 1)
        let small = TabletArea(x: 0.3, y: 0.3, width: 0.3, height: 0.2)
        s.tabletPresets = [TabletPreset(name: "osu!", area: small, lockAspect: false, appBundleID: "sh.ppy.osu.lazer", appName: "osu!")]
        XCTAssertEqual(s.effective(for: "sh.ppy.osu.lazer").tabletArea, small)
        XCTAssertEqual(s.effective(for: "com.seriflabs.affinityphoto2").tabletArea, s.tabletArea)
        XCTAssertEqual(s.effective(for: nil).tabletArea, s.tabletArea)
    }

    func testDefaultTabletAreaIsFullArea() {
        XCTAssertEqual(InputSettings().tabletArea, .full)
        XCTAssertTrue(TabletPreset.fullArea.matches(.full))
        XCTAssertTrue(TabletPreset.fullArea.isBuiltIn)
    }

    func testTabletModeRestartsStream() {
        let a = ClientConfig(viewPixelWidth: 10, viewPixelHeight: 10, quality: StreamQuality())
        var b = a; b.tabletMode = true
        XCTAssertFalse(b.sameStream(as: a))
    }
}

final class PluginWireTests: XCTestCase {
    func testPluginActionAndButtonRoundTrip() throws {
        var s = InputSettings()
        s.squeeze = .plugin("squeeze-scroll/toggle")
        s.radialMenu.append(ShortcutButton(title: "Layer", shortcut: Shortcut("n", [.command, .shift]), pluginAction: "x/new-layer"))
        XCTAssertEqual(try JSONDecoder().decode(InputSettings.self, from: JSONEncoder().encode(s)), s)
        let old = try JSONDecoder().decode(ShortcutButton.self, from: Data(#"{"id":"8D2E3F4A-1B2C-4D5E-8F90-123456789ABC","title":"Undo","shortcut":{"key":"z","modifiers":1}}"#.utf8))
        XCTAssertNil(old.pluginAction)
        let a = [PluginActionInfo(id: "p/a", title: "A", icon: "star", plugin: "P")]
        XCTAssertEqual(try JSONWire.decode([PluginActionInfo].self, JSONWire.encode(a)), a)
    }
}

final class TabletExtrasTests: XCTestCase {
    func testRotatedAreaMapsCornersAndCentre() {
        let size = CGSize(width: 1000, height: 800)
        var a = TabletArea(x: 0.2, y: 0.25, width: 0.5, height: 0.5)
        a.rotation = 90
        let c = a.corners(in: size)
        // Rotated corner "top-left" maps back to (0, 0) of the area.
        let n = a.normalized(c[0], in: size)
        XCTAssertEqual(Double(n.x), 0, accuracy: 0.001); XCTAssertEqual(Double(n.y), 0, accuracy: 0.001)
        let m = a.normalized(CGPoint(x: a.rect(in: size).midX, y: a.rect(in: size).midY), in: size)
        XCTAssertEqual(Double(m.x), 0.5, accuracy: 0.001); XCTAssertEqual(Double(m.y), 0.5, accuracy: 0.001)
        let br = a.normalized(c[2], in: size)
        XCTAssertEqual(Double(br.x), 1, accuracy: 0.001); XCTAssertEqual(Double(br.y), 1, accuracy: 0.001)
    }

    func testOldAreaWithoutRotationDecodes() throws {
        let a = try JSONDecoder().decode(TabletArea.self, from: Data(#"{"x":0.1,"y":0.2,"width":0.3,"height":0.4}"#.utf8))
        XCTAssertEqual(a.rotation, 0); XCTAssertEqual(a.width, 0.3)
    }

    func testTipGate() {
        var g = TipGate()
        XCTAssertEqual(g.phase(for: .down, pressure: 0.1, threshold: 0.3), .hover)
        XCTAssertEqual(g.phase(for: .move, pressure: 0.35, threshold: 0.3), .down)
        XCTAssertEqual(g.phase(for: .move, pressure: 0.25, threshold: 0.3), .move)    // hysteresis
        XCTAssertEqual(g.phase(for: .move, pressure: 0.2, threshold: 0.3), .up)
        XCTAssertEqual(g.phase(for: .up, pressure: 0, threshold: 0.3), nil)
        var off = TipGate()
        XCTAssertEqual(off.phase(for: .down, pressure: 0.01, threshold: 0), .down)
    }

    func testKeyColumnVerticalPosition() {
        var k = TabletKeys()
        k.vertical = 0
        XCTAssertEqual(Double(k.frames(in: CGSize(width: 1180, height: 820))[0].minY), 22, accuracy: 0.5)
        k.vertical = 1
        let f = k.frames(in: CGSize(width: 1180, height: 820))
        XCTAssertEqual(Double(f.last!.maxY), 820 - 22, accuracy: 0.5)
    }

    func testKeyRowAtTheTop() {
        var k = TabletKeys(); k.side = .top; k.vertical = 0
        let f = k.frames(in: CGSize(width: 1180, height: 820))
        XCTAssertEqual(Double(f[0].minY), 22, accuracy: 0.5)
        XCTAssertEqual(Double(f[0].minX), 22, accuracy: 0.5)
        XCTAssertEqual(Double(f[1].minY), Double(f[0].minY), accuracy: 0.01)   // side by side
        XCTAssertGreaterThan(f[1].minX, f[0].maxX)
    }

    func testProfileRoundTrip() throws {
        var s = InputSettings(); s.tabletMode = true; s.tipThreshold = 0.2
        let p = SettingsProfile(name: "osu!", settings: s, quality: StreamQuality(fps: 60))
        XCTAssertEqual(try JSONDecoder().decode(SettingsProfile.self, from: JSONEncoder().encode(p)), p)
    }

    func testKeyFramesOnTheChosenSide() {
        var k = TabletKeys(); k.side = .right
        let f = k.frames(in: CGSize(width: 1180, height: 820))
        XCTAssertEqual(f.count, 2)
        XCTAssertGreaterThan(f[0].minX, 1000)
        XCTAssertLessThan(f[0].maxY, f[1].minY)
    }
}
