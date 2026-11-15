import Foundation
import AppKit
import ScreenCaptureKit
import CoreGraphics
import TafelKit

enum CaptureMode: String, CaseIterable, Identifiable {
    case display, region, window
    var id: String { rawValue }
    var title: String {
        switch self {
        case .region: return "iPad-Ausschnitt"
        case .display: return "Ganzer Bildschirm"
        case .window: return "Fenster"
        }
    }
    var symbol: String {
        switch self {
        case .region: return "ipad.landscape"
        case .display: return "display"
        case .window: return "macwindow"
        }
    }
    var help: String {
        switch self {
        case .region: return "Ausschnitt im iPad-Seitenverhältnis, füllt das iPad ohne schwarze Ränder."
        case .display: return "Ganzer Bildschirm; bei abweichendem Seitenverhältnis gibt es Ränder auf dem iPad."
        case .window: return "Ein einzelnes Fenster (z. B. Affinity). Position wird alle 0,5 s nachgeführt."
        }
    }
}

struct DisplayChoice: Identifiable, Hashable {
    let id: CGDirectDisplayID
    let title: String
}

struct WindowChoice: Identifiable, Hashable {
    let id: CGWindowID
    let title: String
}

@MainActor
final class HostController: ObservableObject {
    // Status
    @Published var listenerStatus = "Startet …"
    @Published var sessionDevice: String?
    @Published var sessionLink = ""
    @Published var clientDiagnostics = ""
    @Published var peerToPeer = UserDefaults.standard.bool(forKey: "peerToPeer") {
        didSet {
            guard peerToPeer != oldValue else { return }
            UserDefaults.standard.set(peerToPeer, forKey: "peerToPeer")
            server.peerToPeer = peerToPeer
            server.start(key: hostKey)
        }
    }
    @Published var streamDescription = ""
    @Published var stats = StreamStats()
    @Published var lastError: String?
    @Published var screenRecordingGranted = CGPreflightScreenCaptureAccess()
    @Published var accessibilityGranted = InputInjector.isTrusted

    // Pairing
    @Published var pairingCode: String?
    @Published var pairingSecondsLeft = 0
    @Published var lastPaired: String?

    // Source
    /// Default: whole screen. The user's choice is remembered.
    @Published var mode: CaptureMode = CaptureMode(rawValue: UserDefaults.standard.string(forKey: "captureMode") ?? "") ?? .display {
        didSet {
            guard mode != oldValue else { return }
            UserDefaults.standard.set(mode.rawValue, forKey: "captureMode")
            restartStream()
        }
    }
    @Published var displays: [DisplayChoice] = []
    @Published var windows: [WindowChoice] = []
    @Published var selectedDisplay: CGDirectDisplayID = CGMainDisplayID() { didSet { if selectedDisplay != oldValue { restartStream() } } }
    @Published var selectedWindow: CGWindowID = 0 { didSet { if selectedWindow != oldValue, mode == .window { restartStream() } } }
    @Published var regionZoom: Double = 1 { didSet { updateRegionLive() } }
    @Published var regionAnchorX: Double = 0.5 { didSet { updateRegionLive() } }
    @Published var regionAnchorY: Double = 0.5 { didSet { updateRegionLive() } }

    let hostID: String
    let hostName: String
    private(set) var hostKey: Data

    private let server = HostServer()
    private let injector = InputInjector()
    private var streamer: ScreenStreamer?
    private var clientConfig: ClientConfig?
    private var scDisplays: [CGDirectDisplayID: SCDisplay] = [:]
    private var scWindows: [CGWindowID: SCWindow] = [:]
    private var restartTask: Task<Void, Never>?
    private var pairingTimer: Timer?
    private var windowTracker: Timer?
    private var permissionTimer: Timer?
    private var currentRegionLocal: CGRect = .zero
    private var ownApps: [SCRunningApplication] = []
    /// Own windows that *should* be mirrored (the pen test window).
    private var ownVisibleWindows: [SCWindow] = []
    /// Thread-safe copy of the stream description for the network queue.
    private let sourceSnapshot = LockedString()

    private static let hostKeyAccount = "host-key"

    init() {
        let defaults = UserDefaults.standard
        if let id = defaults.string(forKey: "hostID") {
            hostID = id
        } else {
            hostID = UUID().uuidString
            defaults.set(hostID, forKey: "hostID")
        }
        hostName = Host.current().localizedName ?? "Mac"
        if let k = Keychain.get(account: Self.hostKeyAccount), k.count == 32 {
            hostKey = k
        } else {
            hostKey = HostKey.generate()
            Keychain.set(hostKey, account: Self.hostKeyAccount)
        }
        wireServer()
        server.peerToPeer = peerToPeer
        server.start(key: hostKey)
        Task { await refreshSources() }
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.screenRecordingGranted = CGPreflightScreenCaptureAccess()
                self?.accessibilityGranted = InputInjector.isTrusted
            }
        }
    }

    var keyFingerprint: String { HostKey.fingerprint(hostKey) }

    // MARK: Server wiring

    private func wireServer() {
        server.hostID = hostID
        server.hostName = hostName
        let injector = self.injector
        let desc = self.sourceSnapshot
        server.sourceDescription = { desc.value }
        // Pen and scroll go straight from the network queue to CGEvent (no main-thread hop).
        server.onPen = { injector.handle($0) }
        server.onScroll = { injector.scroll($0) }
        server.onShortcut = { s in DispatchQueue.main.async { injector.shortcut(s) } }
        // Keys stay on the network queue (same queue as pen input, keeps their order).
        server.onKey = { injector.key($0) }
        server.onMouse = { injector.pointer($0) }
        server.onText = { injector.text($0) }
        server.onRequestKeyframe = { [weak self] in
            Task { @MainActor in self?.streamer?.requestKeyframe() }
        }
        server.onVideoConnected = { [weak self] in
            Task { @MainActor in
                if self?.streamer == nil { self?.restartStream() } else { self?.streamer?.requestKeyframe() }
            }
        }
        server.onClientConfig = { [weak self] cfg in
            Task { @MainActor in
                guard let self else { return }
                if let d = cfg.diagnostics, d != self.clientConfig?.diagnostics {
                    self.clientDiagnostics = d
                    NSLog("Tafel iPad-Diagnose: %@", d)
                }
                let restart = !cfg.sameStream(as: self.clientConfig)
                self.clientConfig = cfg
                if restart { self.restartStream() }
            }
        }
        server.onSession = { [weak self] name, link in
            if name == nil { injector.releaseAll() }
            Task { @MainActor in
                guard let self else { return }
                self.sessionDevice = name
                self.sessionLink = link
                if name == nil {
                    self.clientConfig = nil
                    await self.stopStream()
                }
            }
        }
        server.onPaired = { [weak self] name in
            Task { @MainActor in
                self?.lastPaired = name
                self?.endPairing()
            }
        }
        server.onStatus = { [weak self] s in Task { @MainActor in self?.listenerStatus = s } }
    }

    // MARK: Permissions

    func requestScreenRecording() {
        _ = CGRequestScreenCaptureAccess()
        Task { await refreshSources() }
    }

    func requestAccessibility() {
        InputInjector.requestTrust()
    }

    // MARK: Pairing

    func beginPairing() {
        let code = PairingCode.generate()
        pairingCode = code
        pairingSecondsLeft = 120
        server.startPairing(code: code, hostKey: hostKey)
        pairingTimer?.invalidate()
        pairingTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.pairingSecondsLeft -= 1
                if self.pairingSecondsLeft <= 0 { self.endPairing() }
            }
        }
    }

    func endPairing() {
        pairingTimer?.invalidate()
        pairingTimer = nil
        pairingCode = nil
        server.stopPairing()
    }

    /// Generates a new host key: every paired iPad must pair again.
    func unpairAll() {
        hostKey = HostKey.generate()
        Keychain.set(hostKey, account: Self.hostKeyAccount)
        server.disconnectSession()
        server.start(key: hostKey)
    }

    // MARK: Sources

    func refreshSources() async {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
            scDisplays = Dictionary(uniqueKeysWithValues: content.displays.map { ($0.displayID, $0) })
            displays = content.displays.map { d in
                let name = NSScreen.screens.first { ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID) == d.displayID }?.localizedName
                return DisplayChoice(id: d.displayID, title: "\(name ?? "Display \(d.displayID)") (\(Int(d.frame.width))×\(Int(d.frame.height)) pt)")
            }
            let own = Bundle.main.bundleIdentifier
            ownApps = content.applications.filter { $0.bundleIdentifier == own }
            ownVisibleWindows = content.windows.filter { $0.owningApplication?.bundleIdentifier == own && $0.title == "Stifttest" }
            let candidates = content.windows.filter {
                $0.windowLayer == 0 && $0.frame.width > 100 && $0.frame.height > 100 && $0.owningApplication?.bundleIdentifier != own
            }
            scWindows = Dictionary(uniqueKeysWithValues: candidates.map { ($0.windowID, $0) })
            windows = candidates.map {
                WindowChoice(id: $0.windowID, title: "\($0.owningApplication?.applicationName ?? "?") – \($0.title ?? "Fenster")")
            }
            if scDisplays[selectedDisplay] == nil, let first = content.displays.first { selectedDisplay = first.displayID }
            if selectedWindow == 0 || scWindows[selectedWindow] == nil {
                selectedWindow = candidates.first { $0.owningApplication?.applicationName.localizedCaseInsensitiveContains("affinity") == true }?.windowID
                    ?? candidates.first?.windowID ?? 0
            }
            screenRecordingGranted = CGPreflightScreenCaptureAccess()
        } catch {
            lastError = "Bildschirminhalte nicht verfügbar – Bildschirmaufnahme erlauben? (\(error.localizedDescription))"
        }
    }

    // MARK: Streaming

    func restartStream() {
        restartTask?.cancel()
        restartTask = Task { [weak self] in
            // Debounce rapid config changes (rotation, slider moves).
            try? await Task.sleep(nanoseconds: 150_000_000)
            guard let self, !Task.isCancelled else { return }
            await self.stopStream()
            await self.startStreamIfPossible()
        }
    }

    private func stopStream() async {
        windowTracker?.invalidate()
        windowTracker = nil
        if let s = streamer {
            streamer = nil
            await s.stop()
        }
        stats = StreamStats()
    }

    private func startStreamIfPossible() async {
        guard let cfg = clientConfig, server.hasVideo || sessionDevice != nil else { return }
        // Always refresh: our own windows must be known so they can be excluded from capture
        // (at app launch the main window may not have been on screen yet).
        await refreshSources()
        lastError = nil
        let streamer = ScreenStreamer()
        let server = self.server
        let injector = self.injector
        // Drop captured frames while more than ~2 frames are queued on the socket.
        let maxBacklog = max(Int(cfg.quality.bitrateMbps * 1_000_000 / 8 / Double(max(cfg.quality.fps, 1))) * 2, 256 * 1024)
        streamer.shouldEncode = { server.videoBacklog < maxBacklog }
        streamer.onEncoded = { format, frame in server.sendVideo(format: format, frame: frame) }
        streamer.onAudio = { server.sendAudio($0) }
        streamer.onStats = { [weak self] s in Task { @MainActor in self?.stats = s } }
        streamer.onStopped = { [weak self] e in
            Task { @MainActor in
                self?.lastError = "Aufnahme gestoppt: \(e?.localizedDescription ?? "unbekannt")"
                self?.streamer = nil
            }
        }

        do {
            switch mode {
            case .region, .display:
                guard let display = scDisplays[selectedDisplay] ?? scDisplays.values.first else {
                    lastError = "Kein Bildschirm gefunden."
                    return
                }
                let local = CGRect(origin: .zero, size: display.frame.size)
                let rect: CGRect
                if mode == .region {
                    let aspect = Double(cfg.viewPixelWidth) / Double(max(cfg.viewPixelHeight, 1))
                    rect = Geometry.region(aspect: aspect, in: local, zoom: regionZoom,
                                           anchor: CGPoint(x: regionAnchorX, y: regionAnchorY))
                } else {
                    rect = local
                }
                currentRegionLocal = rect
                let size = Geometry.streamSize(sourceAspect: Double(rect.width / rect.height),
                                               targetWidth: cfg.viewPixelWidth, targetHeight: cfg.viewPixelHeight,
                                               scale: cfg.quality.resolutionScale)
                // Our own window is never mirrored onto the iPad.
                let filter = SCContentFilter(display: display, excludingApplications: ownApps, exceptingWindows: ownVisibleWindows)
                injector.region = rect.offsetBy(dx: display.frame.minX, dy: display.frame.minY)
                try await streamer.start(filter: filter, sourceRect: rect, width: size.width, height: size.height, quality: cfg.quality)
            case .window:
                guard let window = scWindows[selectedWindow] else {
                    lastError = "Kein Fenster gewählt."
                    return
                }
                let size = Geometry.streamSize(sourceAspect: Double(window.frame.width / window.frame.height),
                                               targetWidth: cfg.viewPixelWidth, targetHeight: cfg.viewPixelHeight,
                                               scale: cfg.quality.resolutionScale)
                injector.region = window.frame
                let filter = SCContentFilter(desktopIndependentWindow: window)
                try await streamer.start(filter: filter, sourceRect: nil, width: size.width, height: size.height, quality: cfg.quality)
                trackWindow(window.windowID)
            }
            self.streamer = streamer
            streamDescription = "\(mode.title) · " + streamer.encoderDescription
            sourceSnapshot.value = streamDescription
            server.sendHostInfo()
            streamer.requestKeyframe()
        } catch {
            lastError = "Stream konnte nicht starten: \(error.localizedDescription)"
            await streamer.stop()
        }
    }

    private func updateRegionLive() {
        guard mode == .region, let cfg = clientConfig, let streamer,
              let display = scDisplays[selectedDisplay] else { return }
        let local = CGRect(origin: .zero, size: display.frame.size)
        let aspect = Double(cfg.viewPixelWidth) / Double(max(cfg.viewPixelHeight, 1))
        let rect = Geometry.region(aspect: aspect, in: local, zoom: regionZoom, anchor: CGPoint(x: regionAnchorX, y: regionAnchorY))
        guard rect != currentRegionLocal else { return }
        currentRegionLocal = rect
        injector.region = rect.offsetBy(dx: display.frame.minX, dy: display.frame.minY)
        let w = streamer.outputWidth, h = streamer.outputHeight
        Task { await streamer.updateSourceRect(rect, width: w, height: h, fps: cfg.quality.fps) }
    }

    /// Keeps Pencil mapping aligned when the captured window moves. Uses the public
    /// CGWindowList API (bounds only, no window contents).
    private func trackWindow(_ id: CGWindowID) {
        windowTracker?.invalidate()
        let injector = self.injector
        windowTracker = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            guard let info = CGWindowListCopyWindowInfo([.optionIncludingWindow], id) as? [[String: Any]],
                  let b = info.first?[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: b) else { return }
            if injector.region != rect { injector.region = rect }
        }
    }
}

final class LockedString: @unchecked Sendable {
    private let lock = NSLock()
    private var _value = ""
    var value: String {
        get { lock.withLock { _value } }
        set { lock.withLock { _value = newValue } }
    }
}
