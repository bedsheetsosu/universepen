import Foundation
import CoreGraphics
import ObjectiveC

/// An extra, virtual Mac display in the iPad's resolution ("second screen" like Sidecar).
///
/// ⚠️ Uses the PRIVATE `CGVirtualDisplay` API (see Private/CGVirtualDisplayPrivate.h). It is the
/// only private API in Tafel and only used when the user picks "Zweiter Bildschirm". The display
/// disappears when this object is released (or the app quits); macOS then moves its windows back.
final class VirtualDisplay {
    // MARK: Runtime check (private API may change with any macOS update)

    struct Availability {
        let isAvailable: Bool
        /// "Class" or "Class -selector" entries that are missing.
        let missing: [String]
    }

    /// Everything Tafel calls, per class. Checked once before the first use.
    private static let required: [(cls: String, selectors: [String])] = [
        ("CGVirtualDisplayDescriptor", ["init", "setDispatchQueue:", "setName:", "setMaxPixelsWide:", "setMaxPixelsHigh:",
                                        "setSizeInMillimeters:", "setProductID:", "setVendorID:", "setSerialNum:",
                                        "setTerminationHandler:"]),
        ("CGVirtualDisplayMode", ["initWithWidth:height:refreshRate:", "width", "height"]),
        ("CGVirtualDisplaySettings", ["init", "setModes:", "setHiDPI:"]),
        ("CGVirtualDisplay", ["initWithDescriptor:", "applySettings:", "displayID"]),
    ]

    static let availability: Availability = {
        var missing: [String] = []
        for (name, selectors) in required {
            guard let cls = NSClassFromString(name) else { missing.append(name); continue }
            for sel in selectors where !cls.instancesRespond(to: NSSelectorFromString(sel)) {
                missing.append("\(name) -\(sel)")
            }
        }
        if !missing.isEmpty { logWhatExists(missing: missing) }
        return Availability(isAvailable: missing.isEmpty, missing: missing)
    }()

    /// On mismatch, log what this macOS actually offers – that is what an update of
    /// CGVirtualDisplayPrivate.h needs.
    private static func logWhatExists(missing: [String]) {
        NSLog("Tafel: second screen unavailable on %@ – missing: %@",
              ProcessInfo.processInfo.operatingSystemVersionString, missing.joined(separator: ", "))
        for (name, _) in required {
            guard let cls = NSClassFromString(name) else { continue }
            var count: UInt32 = 0
            guard let list = class_copyMethodList(cls, &count) else { continue }
            let names = (0..<Int(count)).map { NSStringFromSelector(method_getName(list[$0])) }.sorted()
            free(list)
            NSLog("Tafel: %@ methods: %@", name, names.joined(separator: " "))
        }
    }

    let pixelWidth: Int
    let pixelHeight: Int
    private var display: CGVirtualDisplay?

    var displayID: CGDirectDisplayID { display?.displayID ?? 0 }

    /// `pixelWidth/Height`: the iPad's full-screen pixels. The display runs HiDPI (2×), so it
    /// has the iPad's point size – UI comes out at the same physical size as on the iPad.
    init?(pixelWidth: Int, pixelHeight: Int, name: String = "UniversePen (iPad)") {
        guard Self.availability.isAvailable else { return nil }
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        let w = UInt32(pixelWidth), h = UInt32(pixelHeight)

        let descriptor = CGVirtualDisplayDescriptor()
        descriptor.setDispatchQueue(DispatchQueue.main)
        descriptor.name = name
        descriptor.maxPixelsWide = w
        descriptor.maxPixelsHigh = h
        // Physical size of an 11" iPad panel, so macOS picks a sensible default scale.
        let landscape = pixelWidth >= pixelHeight
        descriptor.sizeInMillimeters = landscape ? CGSize(width: 229, height: 159) : CGSize(width: 159, height: 229)
        descriptor.vendorID = 0x7AFE
        descriptor.productID = 0x0001
        descriptor.serialNum = 0x0001
        descriptor.terminationHandler = { _, _ in }

        guard let d = CGVirtualDisplay(descriptor: descriptor) else { return nil }
        let settings = CGVirtualDisplaySettings()
        settings.hiDPI = 1
        settings.modes = [
            CGVirtualDisplayMode(width: w / 2, height: h / 2, refreshRate: 60),  // HiDPI: iPad point size
            CGVirtualDisplayMode(width: w, height: h, refreshRate: 60),
        ]
        guard d.apply(settings) else { return nil }
        display = d
        selectHiDPIMode()
    }

    /// Prefer the 2× mode (public CGDisplay API), otherwise text would be tiny.
    private func selectHiDPIMode() {
        let id = displayID
        let options = [kCGDisplayShowDuplicateLowResolutionModes: kCFBooleanTrue] as CFDictionary
        guard let modes = CGDisplayCopyAllDisplayModes(id, options) as? [CGDisplayMode],
              let mode = modes.first(where: { $0.width == pixelWidth / 2 && $0.pixelWidth == pixelWidth }) else { return }
        var config: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&config) == .success else { return }
        CGConfigureDisplayWithDisplayMode(config, id, mode, nil)
        CGCompleteDisplayConfiguration(config, .forSession)
    }

    deinit {
        display = nil
    }
}
