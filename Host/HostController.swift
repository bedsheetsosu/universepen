import Foundation
import AppKit
import ScreenCaptureKit
import CoreGraphics
import TafelKit
import Combine

enum CaptureMode: String, CaseIterable, Identifiable {
    case display, virtual, region, window
    var id: String { rawValue }
    var title: String {
        switch self {
        case .region: return L("iPad-Ausschnitt")
        case .display: return L("Ganzer Bildschirm")
        case .virtual: return L("Zweiter Bildschirm")
        case .window: return L("Fenster")
        }
    }
    var symbol: String {
        switch self {
        case .region: return "ipad.landscape"
        case .display: return "display"
        case .virtual: return "rectangle.on.rectangle"
        case .window: return "macwindow"
        }
    }
    var help: String {
        switch self {
        case .region: return L("Ausschnitt im iPad-Seitenverhältnis, füllt das iPad ohne schwarze Ränder.")
        case .virtual: return L("Das iPad wird ein zusätzlicher Mac-Bildschirm (wie Sidecar), randlos in iPad-Auflösung. Anordnen unter Systemeinstellungen → Displays. Experimentell: nutzt eine nicht dokumentierte macOS-Schnittstelle (CGVirtualDisplay) und kann mit macOS-Updates aufhören zu funktionieren.")
        case .display: return L("Ganzer Bildschirm; bei abweichendem Seitenverhältnis gibt es Ränder auf dem iPad.")
        case .window: return L("Ein einzelnes Fenster (z. B. Affinity). Position wird alle 0,5 s nachgeführt.")
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
    @Published var listenerStatus = L("Startet …")
    /// Titles of the pen-test window in both languages (the window keeps the title it was opened with).
    /// The pen test window's title in every app language (it keeps the title it was opened with).
    static let penTestTitles: Set<String> = L10n.allTranslations(of: "Stifttest")
    /// Listener is up (status texts start with "Bereit"/"Ready", depending on the language at the time).
    @Published var listenerReady = false
    @Published var sessionDevice: String?
    @Published var sessionLink = ""
    @Published var clientDiagnostics = ""
    /// iPad battery 0…1 and charging state, as reported by the iPad (nil = unknown / not connected).
    // Time-lapse recording
    @Published var timelapseRunning = false
    @Published var timelapseFrames: Int64 = 0
    @Published var timelapseStarted: Date?
    @Published var timelapseLastFile: URL?
    @Published var timelapseSpeed = UserDefaults.standard.object(forKey: "timelapseSpeed") as? Int ?? 30 {
        didSet { UserDefaults.standard.set(timelapseSpeed, forKey: "timelapseSpeed") }
    }
    private let timelapseSink = TimelapseSink()

    @Published var ipadBattery: Double?
    @Published var ipadCharging: Bool?
    // MARK: Developer API state
    let devAPI = DeveloperAPI()
    @Published var devAPIClients = 0
    @Published var devAPIError: String?
    @Published var devAPIEnabled = UserDefaults.standard.bool(forKey: "devAPI") {
        didSet {
            guard devAPIEnabled != oldValue else { return }
            UserDefaults.standard.set(devAPIEnabled, forKey: "devAPI")
            applyDevAPI()
        }
    }
    /// Last settings snapshot reported by the iPad.
    private var clientSettingsJSON: [String: Any]?
    private var frontAppInfo: AppInfo?

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
    @Published var mode: CaptureMode = HostController.initialMode {
        didSet {
            guard mode != oldValue else { return }
            if mode == .virtual && !Self.secondScreenAvailable { mode = oldValue; return }
            UserDefaults.standard.set(mode.rawValue, forKey: "captureMode")
            if oldValue == .virtual { removeVirtualDisplay() }
            restartStream()
            emitDisplay()
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
    /// Whether the private API for "Zweiter Bildschirm" matches what Tafel expects on this macOS.
    static let secondScreenAvailable = VirtualDisplay.availability.isAvailable

    /// Saved mode, falling back to the whole screen if the second screen is unavailable now.
    private static var initialMode: CaptureMode {
        let saved = CaptureMode(rawValue: UserDefaults.standard.string(forKey: "captureMode") ?? "") ?? .display
        return saved == .virtual && !secondScreenAvailable ? .display : saved
    }

    /// The extra display of the "Zweiter Bildschirm" mode (private API, see VirtualDisplay).
    private var virtualDisplay: VirtualDisplay?
    private var virtualTeardown: Task<Void, Never>?
    @Published var virtualDisplayError: String?
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
        setupDevAPI()
        observeFrontApp()
        observeDisplayChanges()
        observeSources()
        let sink = timelapseSink
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: nil) { _ in
            sink.recorder?.stopAndWait()
        }
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

    // MARK: Developer API (localhost JSON, see SDK/README.md)

    private func setupDevAPI() {
        devAPI.onClientsChanged = { [weak self] n in self?.devAPIClients = n }
        devAPI.handler = { [weak self] method, params in
            guard let self else { throw DeveloperAPI.APIError("Not ready") }
            return try await self.handleAPI(method, params)
        }
        applyDevAPI()
    }

    private func applyDevAPI() {
        devAPI.stop()
        devAPIError = nil
        guard devAPIEnabled else { return }
        do { try devAPI.start() } catch {
            devAPIError = L("Entwickler-API konnte nicht starten: %@", error.localizedDescription)
        }
    }

    nonisolated static func modeName(_ m: CaptureMode) -> String {
        switch m {
        case .display: return "display"
        case .virtual: return "second-screen"
        case .region: return "region"
        case .window: return "window"
        }
    }

    nonisolated static func penPhaseName(_ p: PenPhase) -> String {
        ["hover", "down", "move", "up", "enter", "exit", "cancel"][Int(p.rawValue)]
    }

    nonisolated static func modifierNames(_ m: ModifierSet) -> [String] {
        var r: [String] = []
        if m.contains(.command) { r.append("cmd") }
        if m.contains(.shift) { r.append("shift") }
        if m.contains(.option) { r.append("option") }
        if m.contains(.control) { r.append("control") }
        return r
    }

    nonisolated static func modifierSet(_ names: [String]) -> ModifierSet {
        var m: ModifierSet = []
        for n in names.map({ $0.lowercased() }) {
            switch n {
            case "cmd", "command", "⌘": m.insert(.command)
            case "shift", "⇧": m.insert(.shift)
            case "option", "alt", "opt", "⌥": m.insert(.option)
            case "control", "ctrl", "⌃": m.insert(.control)
            default: break
            }
        }
        return m
    }

    func statusInfo() -> [String: Any] {
        [
            "connected": sessionDevice != nil,
            "device": sessionDevice ?? NSNull(),
            "link": sessionLink.isEmpty ? NSNull() : sessionLink,
            "usb": sessionLink.hasPrefix("USB"),
            "fps": stats.fps, "mbps": stats.mbps, "targetMbps": stats.targetMbps, "dropped": stats.dropped,
            "ipadBattery": ipadBattery ?? NSNull(), "ipadCharging": ipadCharging ?? NSNull(),
        ]
    }

    func displayInfo() -> [String: Any] {
        var second: [String: Any] = ["available": Self.secondScreenAvailable, "active": virtualDisplay != nil]
        if let v = virtualDisplay {
            second["displayID"] = v.displayID
            second["pixelWidth"] = v.pixelWidth
            second["pixelHeight"] = v.pixelHeight
        }
        var stream: [String: Any] = ["running": streamer != nil, "encoder": streamDescription]
        if let cfg = clientConfig {
            stream["ipadPixelWidth"] = cfg.viewPixelWidth
            stream["ipadPixelHeight"] = cfg.viewPixelHeight
            stream["fps"] = cfg.quality.fps
            stream["codec"] = cfg.quality.codec.rawValue
            stream["bitrateMbps"] = cfg.quality.bitrateMbps
            stream["resolutionScale"] = cfg.quality.resolutionScale
            stream["adaptive"] = cfg.quality.adaptive
            stream["fullSource"] = cfg.quality.fullSource
            stream["audio"] = cfg.quality.audio
        }
        if let s = streamer { stream["width"] = s.outputWidth; stream["height"] = s.outputHeight }
        return ["mode": Self.modeName(mode), "modes": CaptureMode.allCases.map(Self.modeName),
                "secondScreen": second, "stream": stream]
    }

    private func emitDisplay() {
        devAPI.emit("display", event: "display", data: displayInfo())
    }

    private func requireSession() throws {
        guard server.hasSession else { throw DeveloperAPI.APIError("No iPad connected") }
    }

    private func patchIPad(_ patch: [String: Any]) throws -> [String: Any] {
        try requireSession()
        guard server.sendSettingsPatch(patch) else { throw DeveloperAPI.APIError("Could not send to the iPad") }
        return ["sent": true]
    }

    private func buttonJSON(_ b: [String: Any]) throws -> Any {
        let title = b["title"] as? String ?? ""
        let key = (b["key"] as? String) ?? "a"
        let mods = Self.modifierSet(b["modifiers"] as? [String] ?? [])
        var hold: HoldKey?
        if let h = (b["hold"] as? String)?.lowercased() {
            let map: [String: HoldKey] = ["shift": .shift, "option": .option, "alt": .option, "cmd": .command,
                                          "command": .command, "control": .control, "ctrl": .control, "space": .space]
            guard let k = map[h] else { throw DeveloperAPI.APIError("Unknown hold key '\(h)'. Use shift, option, cmd, control, space") }
            hold = k
        }
        let btn = ShortcutButton(title: title.isEmpty ? (hold?.symbol ?? key.uppercased()) : title, shortcut: Shortcut(key, mods), hold: hold)
        return try JSONSerialization.jsonObject(with: JSONEncoder().encode(btn))
    }

    func handleAPI(_ method: String, _ p: [String: Any]) async throws -> Any {
        switch method {
        // Status / Display API
        case "status.get":
            return statusInfo()
        case "display.get":
            return displayInfo()
        case "display.setMode":
            let map: [String: CaptureMode] = ["display": .display, "second-screen": .virtual, "virtual": .virtual,
                                              "region": .region, "window": .window]
            guard let name = p["mode"] as? String, let m = map[name] else {
                throw DeveloperAPI.APIError("mode must be one of display, second-screen, region, window")
            }
            if m == .virtual && !Self.secondScreenAvailable { throw DeveloperAPI.APIError("Second screen is not available on this macOS") }
            mode = m
            return displayInfo()
        case "display.setQuality":
            var q: [String: Any] = [:]
            for k in ["fps", "bitrateMbps", "resolutionScale", "adaptive", "audio", "codec"] { if let v = p[k] { q[k] = v } }
            guard !q.isEmpty else { throw DeveloperAPI.APIError("Give at least one of fps, bitrateMbps, resolutionScale, adaptive, audio, codec") }
            return try patchIPad(["quality": q])
        case "app.get":
            return frontAppInfo.map { ["bundleID": $0.bundleID, "name": $0.name] } ?? NSNull()

        // Control API
        case "control.shortcut":
            guard let key = p["key"] as? String, !key.isEmpty else { throw DeveloperAPI.APIError("key is required") }
            guard InputInjector.isTrusted else { throw DeveloperAPI.APIError("Accessibility permission missing") }
            injector.shortcut(Shortcut(key, Self.modifierSet(p["modifiers"] as? [String] ?? [])))
            return ["sent": true]
        case "control.text":
            guard let t = p["text"] as? String else { throw DeveloperAPI.APIError("text is required") }
            injector.text(t)
            return ["sent": true]
        case "control.getSettings":
            try requireSession()
            guard let s = clientSettingsJSON else { throw DeveloperAPI.APIError("The iPad has not reported its settings yet") }
            return s
        case "control.patchSettings":
            var patch: [String: Any] = [:]
            if let s = p["settings"] as? [String: Any] { patch["settings"] = s }
            if let q = p["quality"] as? [String: Any] { patch["quality"] = q }
            guard !patch.isEmpty else { throw DeveloperAPI.APIError("Give settings and/or quality objects") }
            return try patchIPad(patch)
        case "control.setPressureCurve":
            var curve: [String: Any] = [:]
            if let pts = p["points"] as? [[Double]] {
                guard pts.count >= 2, pts.allSatisfy({ $0.count == 2 }) else { throw DeveloperAPI.APIError("points: [[x, y], …] with at least 2 points, x and y in 0…1") }
                curve["points"] = pts.sorted { $0[0] < $1[0] }.map { ["x": min(max($0[0], 0), 1), "y": min(max($0[1], 0), 1)] }
            }
            if let g = p["gamma"] as? Double { curve["gamma"] = g; if p["points"] == nil { curve["points"] = [Any]() } }
            if let m = p["minimum"] as? Double { curve["minimum"] = m }
            guard !curve.isEmpty else { throw DeveloperAPI.APIError("Give points, gamma and/or minimum") }
            return try patchIPad(["settings": ["pressure": curve]])
        case "control.setSmoothing":
            var st: [String: Any] = [:]
            if let v = p["stroke"] as? Double { st["positionSmoothing"] = min(max(v, 0), 1) }
            if let v = p["pressure"] as? Double { st["pressureSmoothing"] = min(max(v, 0), 1) }
            guard !st.isEmpty else { throw DeveloperAPI.APIError("Give stroke and/or pressure (0…1)") }
            return try patchIPad(["settings": st])
        case "control.setAppProfile":
            guard let id = p["bundleID"] as? String, let buttons = p["buttons"] as? [[String: Any]] else {
                throw DeveloperAPI.APIError("bundleID and buttons are required")
            }
            let json = try buttons.map(buttonJSON)
            let name = p["name"] as? String ?? id
            return try patchIPad(["settings": ["appShortcutBars": [id: json], "appNames": [id: name]]])
        case "control.removeAppProfile":
            guard let id = p["bundleID"] as? String else { throw DeveloperAPI.APIError("bundleID is required") }
            return try patchIPad(["removeAppProfiles": [id]])
        case "control.setDefaultBar":
            guard let buttons = p["buttons"] as? [[String: Any]] else { throw DeveloperAPI.APIError("buttons is required") }
            return try patchIPad(["settings": ["shortcutBar": try buttons.map(buttonJSON)]])
        case "api.info":
            return ["api": DeveloperAPI.apiVersion, "app": "UniversePen",
                    "topics": ["input", "gesture", "display", "status", "app"]]
        default:
            throw DeveloperAPI.APIError("Unknown method '\(method)'")
        }
    }

    // MARK: Local control API (URL scheme)

    /// Handles `universepen://…` (also `tafel://…`). Local only: macOS delivers these URLs from
    /// apps on this Mac (Shortcuts, Terminal `open`, Stream Deck …); nothing listens on the network.
    ///   universepen://mode/display | second-screen | region | window
    ///   universepen://pair            open the pairing code
    ///   universepen://pair/stop
    ///   universepen://show            bring the window to the front
    func handle(url: URL) {
        guard ["universepen", "tafel"].contains(url.scheme?.lowercased() ?? "") else { return }
        let parts = ([url.host ?? ""] + url.pathComponents.filter { $0 != "/" }).map { $0.lowercased() }
        switch parts.first {
        case "mode":
            let map: [String: CaptureMode] = ["display": .display, "second-screen": .virtual, "virtual": .virtual,
                                              "region": .region, "window": .window]
            if let name = parts.dropFirst().first, let m = map[name] { mode = m }
        case "pair":
            if parts.dropFirst().first == "stop" { endPairing() } else if pairingCode == nil { beginPairing() }
            NSApp.activate(ignoringOtherApps: true)
        case "show":
            NSApp.activate(ignoringOtherApps: true)
        default:
            NSLog("UniversePen: unknown URL %@", url.absoluteString)
        }
    }

    // MARK: Front app (per-app shortcut bars on the iPad)

    private var frontAppObserver: NSObjectProtocol?

    private func observeFrontApp() {
        let send: (NSRunningApplication?) -> Void = { [weak self] app in
            guard let app, let id = app.bundleIdentifier, id != Bundle.main.bundleIdentifier else { return }
            let info = AppInfo(bundleID: id, name: app.localizedName ?? id)
            self?.server.sendAppInfo(info)
            self?.frontAppInfo = info
            self?.devAPI.emit("app", event: "app", data: ["bundleID": info.bundleID, "name": info.name])
        }
        send(NSWorkspace.shared.frontmostApplication)
        frontAppObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { note in
            send(note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)
        }
    }

    // MARK: Server wiring

    private func wireServer() {
        server.hostID = hostID
        server.hostName = hostName
        let injector = self.injector
        let desc = self.sourceSnapshot
        server.sourceDescription = { desc.value }
        // Pen and scroll go straight from the network queue to CGEvent (no main-thread hop).
        let api = devAPI
        server.onPen = { p in
            injector.handle(p)
            if api.wants("input") {
                let sp = injector.screenPoint(x: p.x, y: p.y)
                api.emit("input", event: "pen", data: [
                    "phase": Self.penPhaseName(p.phase), "x": p.x, "y": p.y, "screenX": sp.x, "screenY": sp.y,
                    "pressure": p.pressure, "tiltX": p.tiltX, "tiltY": p.tiltY, "rotation": p.rotation, "timestamp": p.timestamp,
                ])
            }
        }
        server.onScroll = { e in
            injector.scroll(e)
            if api.wants("input") {
                api.emit("input", event: "scroll", data: ["x": e.x, "y": e.y, "dx": e.dx, "dy": e.dy, "modifiers": Self.modifierNames(e.modifiers)])
            }
        }
        server.onShortcut = { s in
            DispatchQueue.main.async { injector.shortcut(s) }
            if api.wants("input") { api.emit("input", event: "shortcut", data: ["key": s.key, "modifiers": Self.modifierNames(s.modifiers)]) }
        }
        // Keys stay on the network queue (same queue as pen input, keeps their order).
        server.onKey = { k in
            injector.key(k)
            if api.wants("input") { api.emit("input", event: "key", data: ["hidUsage": k.hidUsage, "down": k.down]) }
        }
        server.onMouse = { m in
            injector.pointer(m)
            if api.wants("input") {
                let sp = injector.screenPoint(x: m.x, y: m.y)
                let phase = ["move", "down", "up", "exit"][Int(m.phase.rawValue)]
                api.emit("input", event: "touch", data: ["phase": phase, "button": m.button == .left ? "left" : "right",
                                                          "x": m.x, "y": m.y, "screenX": sp.x, "screenY": sp.y])
            }
        }
        server.onGesture = { g in api.emit("gesture", event: "gesture", data: ["name": g.name, "value": g.value]) }
        server.onClientSettings = { [weak self] o in Task { @MainActor in self?.clientSettingsJSON = o } }
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
                if self.ipadBattery != cfg.batteryLevel { self.ipadBattery = cfg.batteryLevel }
                if self.ipadCharging != cfg.batteryCharging { self.ipadCharging = cfg.batteryCharging }
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
                self.scheduleVirtualTeardown(sessionActive: name != nil)
                if name == nil {
                    self.clientConfig = nil
                    self.ipadBattery = nil
                    self.ipadCharging = nil
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
        server.onReady = { [weak self] r in Task { @MainActor in self?.listenerReady = r } }
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
            ownVisibleWindows = content.windows.filter { $0.owningApplication?.bundleIdentifier == own && HostController.penTestTitles.contains($0.title ?? "") }
            let candidates = content.windows.filter {
                $0.windowLayer == 0 && $0.frame.width > 100 && $0.frame.height > 100 && $0.owningApplication?.bundleIdentifier != own
            }
            scWindows = Dictionary(uniqueKeysWithValues: candidates.map { ($0.windowID, $0) })
            windows = candidates.map {
                WindowChoice(id: $0.windowID, title: "\($0.owningApplication?.applicationName ?? "?") – \($0.title ?? L("Fenster"))")
            }
            if scDisplays[selectedDisplay] == nil, let first = content.displays.first { selectedDisplay = first.displayID }
            if selectedWindow == 0 || scWindows[selectedWindow] == nil {
                selectedWindow = candidates.first { $0.owningApplication?.applicationName.localizedCaseInsensitiveContains("affinity") == true }?.windowID
                    ?? candidates.first?.windowID ?? 0
            }
            screenRecordingGranted = CGPreflightScreenCaptureAccess()
        } catch {
            lastError = L("Bildschirminhalte nicht verfügbar – Bildschirmaufnahme erlauben? (%@)", error.localizedDescription)
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
        if cfg.tabletMode == true {
            startTabletMode()
            return
        }
        let streamer = ScreenStreamer()
        let server = self.server
        let injector = self.injector
        // Drop captured frames while more than ~2 frames are queued on the socket.
        let maxBacklog = max(Int(cfg.quality.bitrateMbps * 1_000_000 / 8 / Double(max(cfg.quality.fps, 1))) * 2, 256 * 1024)
        streamer.shouldEncode = { server.videoBacklog < maxBacklog }
        streamer.onEncoded = { format, frame in server.sendVideo(format: format, frame: frame) }
        streamer.onAudio = { server.sendAudio($0) }
        let sink = timelapseSink
        streamer.onFrame = { sink.append($0, $1) }
        streamer.onStats = { [weak self] s in
            Task { @MainActor in
                guard let self else { return }
                self.stats = s
                if self.devAPI.wants("status") { self.devAPI.emit("status", event: "status", data: self.statusInfo()) }
            }
        }
        streamer.onStopped = { [weak self] e in
            Task { @MainActor in
                self?.lastError = L("Aufnahme gestoppt: %@", e?.localizedDescription ?? L("unbekannt"))
                self?.streamer = nil
            }
        }

        do {
            switch mode {
            case .region, .display, .virtual:
                let chosen: SCDisplay?
                if mode == .virtual {
                    chosen = await ensureVirtualDisplay(width: cfg.viewPixelWidth, height: cfg.viewPixelHeight)
                    if chosen == nil { return }
                } else {
                    chosen = scDisplays[selectedDisplay] ?? scDisplays.values.first
                }
                guard let display = chosen else {
                    lastError = L("Kein Bildschirm gefunden.")
                    return
                }
                let local = CGRect(origin: .zero, size: display.frame.size)
                capturedDisplaySize = display.frame.size
                let rect: CGRect
                if mode == .region {
                    let aspect = Double(cfg.viewPixelWidth) / Double(max(cfg.viewPixelHeight, 1))
                    rect = Geometry.region(aspect: aspect, in: local, zoom: regionZoom,
                                           anchor: CGPoint(x: regionAnchorX, y: regionAnchorY))
                } else {
                    rect = local
                }
                currentRegionLocal = rect
                var size = Geometry.streamSize(sourceAspect: Double(rect.width / rect.height),
                                               targetWidth: cfg.viewPixelWidth, targetHeight: cfg.viewPixelHeight,
                                               scale: cfg.quality.resolutionScale)
                if cfg.quality.fullSource, let full = Self.sourcePixelSize(rect, display: display.displayID, codec: cfg.quality.codec),
                   full.width > size.width {
                    size = full
                }
                // Our own window is never mirrored onto the iPad.
                let filter = SCContentFilter(display: display, excludingApplications: ownApps, exceptingWindows: ownVisibleWindows)
                injector.region = rect.offsetBy(dx: display.frame.minX, dy: display.frame.minY)
                try await streamer.start(filter: filter, sourceRect: rect, width: size.width, height: size.height, quality: cfg.quality)
            case .window:
                guard let window = scWindows[selectedWindow] else {
                    lastError = L("Kein Fenster gewählt.")
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
            lastError = L("Stream konnte nicht starten: %@", error.localizedDescription)
            await streamer.stop()
        }
    }

    /// Backing pixels of `rect` (points) on a display, even, capped to what the encoders and the
    /// iPad's decoder handle (H.264 4096, HEVC 8192 per side).
    static func sourcePixelSize(_ rect: CGRect, display: CGDirectDisplayID, codec: VideoCodec) -> (width: Int, height: Int)? {
        guard let m = CGDisplayCopyDisplayMode(display), m.width > 0 else { return nil }
        let scale = Double(m.pixelWidth) / Double(m.width)
        var w = Double(rect.width) * scale, h = Double(rect.height) * scale
        let cap = codec == .hevc ? 8192.0 : 4096.0
        let f = min(1, cap / max(w, h))
        w *= f; h *= f
        return (max(2, Int(w) & ~1), max(2, Int(h) & ~1))
    }

    // MARK: Tablet mode (no picture, the iPad's active area maps onto a whole display)

    var tabletModeActive: Bool { clientConfig?.tabletMode == true }

    private func startTabletMode() {
        // A blank virtual display would only confuse; it comes back when the picture does.
        if virtualDisplay != nil { removeVirtualDisplay() }
        let id = scDisplays[selectedDisplay] != nil ? selectedDisplay : CGMainDisplayID()
        let bounds = CGDisplayBounds(id)
        injector.region = bounds
        capturedDisplaySize = bounds.size
        let name = displays.first { $0.id == id }?.title ?? "Display"
        streamDescription = L("Tablett-Modus") + " · " + name
        sourceSnapshot.value = streamDescription
        server.sendHostInfo()
    }

    // MARK: Time-lapse

    func startTimelapse() {
        guard !timelapseRunning else { return }
        do {
            let r = try TimelapseRecorder(speed: timelapseSpeed)
            r.onProgress = { [weak self] n in self?.timelapseFrames = n }
            r.onStoppedBySize = { [weak self] url in
                guard let self else { return }
                self.timelapseSink.recorder = nil
                self.timelapseRunning = false
                self.timelapseStarted = nil
                if let url { self.timelapseLastFile = url }
                self.lastError = L("Zeitraffer beendet: Die Bildgröße hat sich geändert (andere Quelle oder Auflösung).")
            }
            timelapseFrames = 0
            timelapseStarted = Date()
            timelapseRunning = true
            timelapseSink.recorder = r
        } catch {
            lastError = L("Zeitraffer konnte nicht starten: %@", error.localizedDescription)
        }
    }

    func stopTimelapse() {
        guard let r = timelapseSink.recorder else { timelapseRunning = false; return }
        timelapseSink.recorder = nil
        timelapseRunning = false
        timelapseStarted = nil
        r.stop { [weak self] url in
            guard let self else { return }
            if let url { self.timelapseLastFile = url } else { self.lastError = L("Zeitraffer war leer – nichts gespeichert.") }
        }
    }

    // MARK: Source menu on the iPad

    private var sourceObservers: Set<AnyCancellable> = []

    private func observeSources() {
        Publishers.CombineLatest4($mode, $displays, $windows, $selectedDisplay)
            .combineLatest($selectedWindow)
            .debounce(for: .milliseconds(200), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.publishSourceList() }
            .store(in: &sourceObservers)
        server.onSelectSource = { [weak self] sel in
            Task { @MainActor in await self?.selectSource(sel) }
        }
    }

    private func publishSourceList() {
        let modes = CaptureMode.allCases.map {
            SourceOption(id: Self.modeName($0), title: $0.title, available: $0 != .virtual || Self.secondScreenAvailable)
        }
        server.sendSourceList(SourceList(
            mode: Self.modeName(mode), modes: modes,
            displays: displays.map { d in
                let b = CGDisplayBounds(d.id)
                return SourceOption(id: String(d.id), title: d.title, aspect: b.height > 0 ? Double(b.width / b.height) : nil)
            }, selectedDisplay: String(selectedDisplay),
            windows: windows.map { SourceOption(id: String($0.id), title: $0.title) }, selectedWindow: String(selectedWindow)))
    }

    private func selectSource(_ sel: SourceSelection) async {
        if sel.refresh == true { await refreshSources(); publishSourceList() }
        if let d = sel.display.flatMap({ CGDirectDisplayID($0) }), scDisplays[d] != nil { selectedDisplay = d }
        if let w = sel.window.flatMap({ CGWindowID($0) }), scWindows[w] != nil { selectedWindow = w }
        if let name = sel.mode, let m = CaptureMode.allCases.first(where: { Self.modeName($0) == name }),
           m != .virtual || Self.secondScreenAvailable {
            if m != mode { mode = m } else if sel.window != nil || sel.display != nil { restartStream() }
        }
    }

    // MARK: Display changes

    private var displayChangeWork: DispatchWorkItem?
    /// Size (points) of the display the running stream captures.
    private var capturedDisplaySize: CGSize?

    /// A resolution change ("more space" etc.) changes the captured size in points: restart the
    /// stream so the picture and the Pencil mapping follow (public CGDisplay API).
    private func observeDisplayChanges() {
        let me = Unmanaged.passUnretained(self).toOpaque()
        CGDisplayRegisterReconfigurationCallback({ id, flags, info in
            guard let info, !flags.contains(.beginConfigurationFlag), flags.contains(.setModeFlag) else { return }
            let host = Unmanaged<HostController>.fromOpaque(info).takeUnretainedValue()
            DispatchQueue.main.async { MainActor.assumeIsolated { host.displayModeChanged(id) } }
        }, me)
    }

    private func displayModeChanged(_ id: CGDirectDisplayID) {
        guard streamer != nil || virtualDisplay != nil || tabletModeActive else { return }
        let affected: Bool
        if tabletModeActive { affected = id == selectedDisplay || id == CGMainDisplayID() } else {
        switch mode {
        case .virtual: affected = id == virtualDisplay?.displayID
        case .display, .region: affected = id == selectedDisplay
        case .window: affected = false
        }
        }
        guard affected, CGDisplayBounds(id).size != capturedDisplaySize else { return }
        if mode == .virtual, let s = virtualDisplay?.currentScale { VirtualDisplay.preferredScale = s }
        displayChangeWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                await self?.refreshSources()
                self?.restartStream()
            }
        }
        displayChangeWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    // MARK: Second screen (virtual display, private API)

    /// Creates (or re-creates after rotation) the virtual display and waits until ScreenCaptureKit
    /// lists it.
    private func ensureVirtualDisplay(width: Int, height: Int) async -> SCDisplay? {
        virtualTeardown?.cancel()
        if let v = virtualDisplay, v.pixelWidth != width || v.pixelHeight != height {
            virtualDisplay = nil   // orientation changed
        }
        if virtualDisplay == nil {
            guard let v = VirtualDisplay(pixelWidth: width, pixelHeight: height) else {
                virtualDisplayError = L("Zweiter Bildschirm ist auf diesem macOS nicht verfügbar (private Schnittstelle fehlt oder wurde geändert).")
                lastError = virtualDisplayError
                return nil
            }
            virtualDisplay = v
            virtualDisplayError = nil
            emitDisplay()
        }
        let id = virtualDisplay!.displayID
        for _ in 0..<20 {
            await refreshSources()
            if let d = scDisplays[id] { return d }
            try? await Task.sleep(nanoseconds: 150_000_000)
        }
        lastError = L("Zweiter Bildschirm wurde angelegt, ist aber für die Aufnahme nicht sichtbar.")
        return nil
    }

    private func removeVirtualDisplay() {
        virtualTeardown?.cancel()
        virtualDisplay = nil
        emitDisplay()
        Task { await refreshSources() }
    }

    /// Without an iPad the extra display would hold windows nobody can see. Keep it through short
    /// drop-outs (USB link resets take ~3 s), remove it after 10 s – macOS then moves the windows back.
    private func scheduleVirtualTeardown(sessionActive: Bool) {
        virtualTeardown?.cancel()
        guard !sessionActive, virtualDisplay != nil else { return }
        virtualTeardown = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 10_000_000_000)
            guard !Task.isCancelled, let self, self.sessionDevice == nil else { return }
            self.removeVirtualDisplay()
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
