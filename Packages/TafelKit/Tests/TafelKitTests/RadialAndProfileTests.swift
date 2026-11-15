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
