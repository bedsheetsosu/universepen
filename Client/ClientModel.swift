import Foundation
import Network
import UIKit
import TafelKit

struct PairedHost: Codable, Identifiable, Hashable {
    var id: String      // host ID from the Mac
    var name: String
    var fingerprint: String
}

struct DiscoveredHost: Identifiable, Hashable {
    var id: String { "\(pairing ? "p" : "m")-\(hostID)-\(name)" }
    var hostID: String
    var name: String
    var endpoint: NWEndpoint
    var pairing: Bool
    /// Non-Wi-Fi interfaces Bonjour found this Mac on (probably the USB cable), best first.
    var cableInterfaces: [NWInterface] = []
}

@MainActor
final class ClientModel: ObservableObject {
    static let shared = ClientModel()

    enum Phase: Equatable {
        case idle
        case connecting(String)
        case connected(String)
        /// Link dropped (e.g. USB drop-out): last picture stays, reconnecting in the background.
        case reconnecting(String)
        case failed(String)

        var showsCanvas: Bool {
            switch self {
            case .connected, .reconnecting: return true
            default: return false
            }
        }
    }

    @Published var phase: Phase = .idle
    @Published var discovered: [DiscoveredHost] = []
    @Published var pairable: [DiscoveredHost] = []
    @Published var paired: [PairedHost] = []
    @Published var hostInfo: HostInfo?
    /// App in front on the Mac.
    @Published var frontApp: AppInfo? {
        didSet { if settings.isGame(frontApp?.bundleID) != settings.isGame(oldValue?.bundleID) { sendConfig() } }
    }
    /// What the Mac can stream (source menu).
    @Published var sourceList: SourceList?
    /// Actions offered by plugins on the Mac.
    @Published var pluginActions: [PluginActionInfo] = []
    /// Message from the Mac (plugins), shown briefly.
    @Published var toast: Toast?
    private var toastHide: DispatchWorkItem?
    /// Undo scrub in progress: steps so far (negative = undo), nil = not scrubbing.
    @Published var scrubSteps: Int?

    /// Game mode is on for the app in front (maximum quality, no smoothing).
    var gameModeActive: Bool { settings.isGame(frontApp?.bundleID) }
    var effectiveQuality: StreamQuality { gameModeActive ? quality.gameMode : quality }

    /// Settings in effect for the app in front on the Mac (its own Pencil profile, if any).
    var effectiveSettings: InputSettings { settings.effective(for: frontApp?.bundleID) }

    /// Radial menu open at this point (canvas/window coordinates), and the item under the Pencil.
    @Published var radialCenter: CGPoint?
    @Published var radialHighlight: Int?

    /// The bar for the app in front, or the standard bar.
    var currentBar: [ShortcutButton] {
        frontApp.flatMap { settings.appShortcutBars[$0.bundleID] } ?? settings.shortcutBar
    }
    @Published var timing: Session.Timing?
    @Published var videoSize: CGSize = .zero
    @Published var pairingBusy = false
    @Published var pairingError: String?
    /// First-run setup finished (shown again via Settings → "Einrichtung erneut starten").
    @Published var onboardingDone = UserDefaults.standard.bool(forKey: "onboardingDone") {
        didSet { UserDefaults.standard.set(onboardingDone, forKey: "onboardingDone") }
    }
    /// Another iPad shows the picture: this one works as a tablet (input only).
    @Published var secondary = false {
        didSet {
            guard secondary != oldValue else { return }
            sendConfig()
            if secondary { show(Toast(text: L("Ein anderes iPad zeigt das Bild – dieses iPad arbeitet als Tablett."), seconds: 3)) }
        }
    }
    /// Tablet mode in effect (switched on, or forced because this iPad is an extra tablet).
    var tabletModeActive: Bool { settings.tabletMode || secondary }

    // MARK: Keep awake / dim when idle

    private var lastInput = Date()
    private var lastPictureChange = Date()
    private var savedBrightness: CGFloat?
    private var idleTimer: Timer?

    private var screen: UIScreen? {
        (UIApplication.shared.connectedScenes.first as? UIWindowScene)?.screen
    }

    /// Any touch, hover or key on the iPad.
    func noteInput() {
        lastInput = Date()
        if savedBrightness != nil { undim() }
    }

    /// Break reminder: counts connected time with input in the last 5 minutes.
    private func checkBreak(live: Bool) {
        let active = live && Date().timeIntervalSince(lastInput) < 300
        guard active else {
            // A pause of 5 minutes counts as the break.
            if drawingSince != nil, Date().timeIntervalSince(lastInput) >= 300 || !live { drawingSince = nil; lastBreakReminder = nil }
            return
        }
        let start = drawingSince ?? Date()
        drawingSince = start
        guard settings.breakReminderMinutes > 0 else { return }
        let every = settings.breakReminderMinutes * 60
        let since = Date().timeIntervalSince(lastBreakReminder ?? start)
        guard since >= every else { return }
        lastBreakReminder = Date()
        let minutes = Int(Date().timeIntervalSince(start) / 60)
        show(Toast(text: L("Du zeichnest seit %d Minuten – kurz die Hand lockern und in die Ferne schauen?", minutes), seconds: 6))
    }

    private func checkIdle() {
        // Never sleep while connected (it would drop the session); dim instead if wanted.
        let live = phase.showsCanvas
        UIApplication.shared.isIdleTimerDisabled = live
        checkBreak(live: live)
        guard live, settings.dimAfterMinutes > 0 else { if savedBrightness != nil { undim() }; return }
        let limit = settings.dimAfterMinutes * 60
        var idle = Date().timeIntervalSince(lastInput) > limit
        if settings.dimOnlyWhenStill { idle = idle && Date().timeIntervalSince(lastPictureChange) > limit }
        if idle, savedBrightness == nil, let s = screen {
            savedBrightness = s.brightness
            s.brightness = min(s.brightness, 0.04)
        } else if !idle, savedBrightness != nil {
            undim()
        }
    }

    private func undim() {
        if let b = savedBrightness { screen?.brightness = b }
        savedBrightness = nil
    }

    /// Demo mode: everything runs on the iPad, no Mac (for showing UniversePen).
    @Published var demoMode = false
    /// On-screen keyboard shown (hardware keyboards work without it).
    @Published var showKeyboard = false
    /// Floating reference photo (iPad only, never sent to the Mac).
    let reference = ReferenceImage()
    /// Virtual ruler on the canvas (strokes near it stay straight).
    /// Floating live palette from the Mac (own object: its frames must not redraw the app).
    let palette = PaletteState()
    /// Picture mirrored on the iPad only.
    @Published var mirrored = false
    private var drawingSince: Date?
    private var lastBreakReminder: Date?

    /// The drawing aid on screen (ruler, perspective, ellipse) – one at a time.
    @Published var guide: DrawingGuide = .none
    var rulerVisible: Bool {
        get { guide == .ruler }
        set { guide = newValue ? .ruler : .none }
    }
    /// Local zoom of the picture (zoom method "only on the iPad"); bump `localZoomResets` to reset.
    @Published var localZoom: CGFloat = 1
    @Published var localZoomResets = 0
    /// Local view rotation in whole degrees (shown in the zoom pill).
    @Published var localAngle = 0
    /// Laser pointer: the Pencil draws fading marks on the Mac screen instead of clicking.
    @Published var laserMode = false { didSet { if laserMode != oldValue { sendConfig() } } }
    /// Screenshot from the Mac waiting to be cropped / shared.
    @Published var screenshot: UIImage?
    @Published var screenshotPending = false

    @Published var settings: InputSettings {
        didSet {
            save(settings, "inputSettings")
            sendSettingsSnapshot()
            if settings.tabletMode != oldValue.tabletMode { sendConfig() }
            storeIntoActiveProfile()
        }
    }

    // MARK: Profiles (named sets of all settings; changes go into the active one)

    @Published var profiles: [SettingsProfile] { didSet { save(profiles, "profiles") } }
    @Published var activeProfileID: UUID? {
        didSet { UserDefaults.standard.set(activeProfileID?.uuidString, forKey: "activeProfile") }
    }
    var activeProfile: SettingsProfile? { profiles.first { $0.id == activeProfileID } }
    private var switchingProfile = false

    private func storeIntoActiveProfile() {
        guard !switchingProfile, let id = activeProfileID, let i = profiles.firstIndex(where: { $0.id == id }) else { return }
        if profiles[i].settings != settings || profiles[i].quality != quality {
            profiles[i].settings = settings
            profiles[i].quality = quality
        }
    }

    /// New profile from the current settings; it becomes the active one.
    func createProfile(named name: String) {
        let n = name.trimmingCharacters(in: .whitespaces)
        let p = SettingsProfile(name: n.isEmpty ? L("Profil %d", profiles.count + 1) : n, settings: settings, quality: quality)
        profiles.append(p)
        activeProfileID = p.id
    }

    func switchProfile(_ p: SettingsProfile) {
        storeIntoActiveProfile()
        switchingProfile = true
        activeProfileID = p.id
        settings = p.settings
        quality = p.quality
        switchingProfile = false
        show(Toast(text: L("Profil: %@", p.name), seconds: 1.2))
    }

    /// Imports profiles from a file (one profile or a list); names that exist get "(2)".
    @discardableResult
    func importProfiles(from data: Data) -> Int {
        let list: [SettingsProfile]
        if let one = try? JSONDecoder().decode(SettingsProfile.self, from: data) { list = [one] }
        else if let many = try? JSONDecoder().decode([SettingsProfile].self, from: data) { list = many }
        else { return 0 }
        for var p in list {
            p.id = UUID()
            var name = p.name, n = 2
            while profiles.contains(where: { $0.name == name }) { name = "\(p.name) (\(n))"; n += 1 }
            p.name = name
            profiles.append(p)
        }
        return list.count
    }

    func duplicateProfile(_ p: SettingsProfile) {
        var copy = p
        copy.id = UUID()
        copy.name = L("%@ Kopie", p.name)
        profiles.append(copy)
    }

    func renameProfile(_ p: SettingsProfile, to name: String) {
        guard let i = profiles.firstIndex(where: { $0.id == p.id }), !name.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        profiles[i].name = name.trimmingCharacters(in: .whitespaces)
    }

    func deleteProfile(_ p: SettingsProfile) {
        profiles.removeAll { $0.id == p.id }
        if activeProfileID == p.id { activeProfileID = nil }
    }
    /// Active area being edited (tablet mode).
    @Published var tabletEditing = false
    /// Width/height of the Mac display the tablet area maps onto.
    var tabletAspect: Double {
        guard let l = sourceList else { return 16.0 / 10.0 }
        return l.displays.first { $0.id == l.selectedDisplay }?.aspect ?? l.displays.first?.aspect ?? 16.0 / 10.0
    }
    @Published var quality: StreamQuality { didSet { save(quality, "quality"); sendConfig(); sendSettingsSnapshot(); storeIntoActiveProfile() } }
    @Published var showStatusOverlay: Bool { didSet { UserDefaults.standard.set(showStatusOverlay, forKey: "showStatusOverlay") } }
    /// Äbbl peer-to-peer Wi-Fi (AWDL). Off by default: it costs Wi-Fi latency.
    @Published var peerToPeer: Bool {
        didSet {
            guard peerToPeer != oldValue else { return }
            UserDefaults.standard.set(peerToPeer, forKey: "peerToPeer")
            startBrowsing()
        }
    }
    /// Best cable candidate of the last-used Mac (diagnostics / settings).
    @Published var cableInterface: NWInterface?
    /// All interfaces this app can see, e.g. "en0 wifi, en2 wired" (diagnostics).
    @Published var visibleInterfaces = ""
    /// Interfaces Bonjour found the Mac on (diagnostics).
    private var browseInterfaces = ""
    var wiredAvailable: Bool { cableInterface != nil }

    let renderer = VideoRenderer()
    let audioPlayer = AudioPlayer()
    private let pathMonitor = NWPathMonitor()
    /// Give up reconnecting after this point (then show the error).
    private var reconnectDeadline: Date?
    private var lastCableFailure = Date.distantPast
    private var backToCableTimer: Timer?
    private(set) var session: Session?
    let deviceID: String
    let deviceName = UIDevice.current.name

    private var browser: NWBrowser?
    private var pairingBrowser: NWBrowser?
    private var pairingAttempt: PairingAttempt?
    private var viewPixelSize: (Int, Int) = (0, 0)
    private var lastHostID: String? {
        get { UserDefaults.standard.string(forKey: "lastHostID") }
        set { UserDefaults.standard.set(newValue, forKey: "lastHostID") }
    }

    init() {
        let d = UserDefaults.standard
        if let id = d.string(forKey: "deviceID") {
            deviceID = id
        } else {
            deviceID = UUID().uuidString
            d.set(deviceID, forKey: "deviceID")
        }
        var loaded = Self.load(InputSettings.self, "inputSettings") ?? InputSettings()
        // v2: three-finger swipes switch desktops. Move users who still have the old, untouched
        // defaults (undo/redo/none/none) to the new ones; customised settings stay as they are.
        if !d.bool(forKey: "swipeDefaultsV2") {
            if loaded.threeFingerSwipeLeft == .undo, loaded.threeFingerSwipeRight == .redo,
               loaded.threeFingerSwipeUp == .none, loaded.threeFingerSwipeDown == .none {
                let fresh = InputSettings()
                loaded.threeFingerSwipeLeft = fresh.threeFingerSwipeLeft
                loaded.threeFingerSwipeRight = fresh.threeFingerSwipeRight
                loaded.threeFingerSwipeUp = fresh.threeFingerSwipeUp
                loaded.threeFingerSwipeDown = fresh.threeFingerSwipeDown
            }
            d.set(true, forKey: "swipeDefaultsV2")
        }
        settings = loaded
        quality = Self.load(StreamQuality.self, "quality") ?? StreamQuality()
        showStatusOverlay = d.bool(forKey: "showStatusOverlay")
        peerToPeer = d.bool(forKey: "peerToPeer")
        paired = Self.load([PairedHost].self, "pairedHosts") ?? []
        profiles = Self.load([SettingsProfile].self, "profiles") ?? []
        activeProfileID = d.string(forKey: "activeProfile").flatMap(UUID.init(uuidString:))
        renderer.onSize = { [weak self] size in self?.videoSize = size }
        renderer.onContentChange = { [weak self] in
            DispatchQueue.main.async { self?.lastPictureChange = Date() }
        }
        idleTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkIdle() }
        }
        NotificationCenter.default.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.undim() }
        }
        NotificationCenter.default.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.cameToForeground() }
        }
        startWiredMonitor()
        startBatteryMonitor()
        startBrowsing()
        backToCableTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkBackToCable() }
        }
    }

    // MARK: Battery (shown in the Mac menu bar)

    private func startBatteryMonitor() {
        UIDevice.current.isBatteryMonitoringEnabled = true
        for n in [UIDevice.batteryLevelDidChangeNotification, UIDevice.batteryStateDidChangeNotification] {
            NotificationCenter.default.addObserver(forName: n, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.sendConfig() }
            }
        }
    }

    private var battery: (level: Double?, charging: Bool?) {
        let d = UIDevice.current
        let level = d.batteryLevel < 0 ? nil : Double(d.batteryLevel)
        switch d.batteryState {
        case .charging, .full: return (level, true)
        case .unplugged: return (level, false)
        default: return (level, nil)
        }
    }

    // MARK: Radial menu

    func openRadial(at p: CGPoint) {
        radialHighlight = nil
        radialCenter = p
    }

    func closeRadial() {
        radialCenter = nil
        radialHighlight = nil
    }

    /// Runs the item (if one is picked) and closes the menu.
    func pickRadial(_ index: Int?) {
        let items = effectiveSettings.radialMenu
        if let i = index, items.indices.contains(i) { run(items[i]) }
        closeRadial()
    }

    // MARK: Cable

    private func startWiredMonitor() {
        pathMonitor.pathUpdateHandler = { [weak self] path in
            let names = path.availableInterfaces.map { "\($0.name) \(Self.typeName($0.type))" }.joined(separator: ", ")
            Task { @MainActor in
                guard let self else { return }
                self.visibleInterfaces = names
                self.sendConfig()
            }
        }
        pathMonitor.start(queue: .main)
    }

    /// The USB link to the Mac is not documented for apps. Candidates: any wired interface, or an
    /// "other" interface that is not a VPN tunnel, AWDL, loopback or cellular.
    nonisolated static func mayBeCable(_ i: NWInterface) -> Bool {
        switch i.type {
        case .wiredEthernet: return true
        case .other:
            let excluded = ["utun", "ipsec", "awdl", "llw", "lo0", "pdp_ip", "bridge", "ap1", "gif", "stf"]
            return !excluded.contains { i.name.hasPrefix($0) }
        default: return false
        }
    }

    nonisolated static func typeName(_ t: NWInterface.InterfaceType) -> String {
        switch t {
        case .wifi: return "wifi"
        case .wiredEthernet: return "wired"
        case .cellular: return "cell"
        case .loopback: return "loop"
        case .other: return "other"
        @unknown default: return "?"
        }
    }

    private var diagnostics: String {
        "sichtbar: [\(visibleInterfaces)] · Bonjour: [\(browseInterfaces)] · Kabel-Kandidat: \(cableInterface?.name ?? "keiner") · Weg: \(timing?.link ?? "–")"
    }

    func startBrowsing() {
        browser?.cancel()
        pairingBrowser?.cancel()
        browser = makeBrowser(TafelNetwork.serviceType, pairing: false)
        pairingBrowser = makeBrowser(TafelNetwork.pairingServiceType, pairing: true)
    }

    private func makeBrowser(_ type: String, pairing: Bool) -> NWBrowser {
        let params = NWParameters()
        params.includePeerToPeer = peerToPeer
        let b = NWBrowser(for: .bonjourWithTXTRecord(type: type, domain: nil), using: params)
        b.browseResultsChangedHandler = { [weak self] results, _ in
            let hosts: [DiscoveredHost] = results.compactMap { r in
                guard case .service(let name, _, _, _) = r.endpoint else { return nil }
                var hostID = ""
                if case .bonjour(let txt) = r.metadata { hostID = txt[TafelNetwork.txtHostIDKey] ?? "" }
                let cable = r.interfaces.filter(Self.mayBeCable)
                    .sorted { ($0.name.hasPrefix("en") ? 0 : 1, $0.name) < ($1.name.hasPrefix("en") ? 0 : 1, $1.name) }
                return DiscoveredHost(hostID: hostID, name: name, endpoint: r.endpoint, pairing: pairing, cableInterfaces: cable)
            }
            let ifaces = Set(results.flatMap { $0.interfaces.map { "\($0.name) \(Self.typeName($0.type))" } }).sorted().joined(separator: ", ")
            Task { @MainActor in
                guard let self else { return }
                if !pairing { self.browseInterfaces = ifaces }
                if pairing { self.pairable = hosts } else { self.discovered = hosts; self.cableAppeared(); self.autoConnect() }
            }
        }
        b.stateUpdateHandler = { [weak self] state in
            if case .failed(let e) = state {
                Task { @MainActor in self?.phase = .failed(L("Suche fehlgeschlagen: %@", e.localizedDescription)) }
            }
        }
        b.start(queue: .main)
        return b
    }

    private func cableAppeared() {
        guard let last = lastHostID, let h = discovered.first(where: { $0.hostID == last }) else { return }
        cableInterface = h.cableInterfaces.first
    }

    /// Running over Wi-Fi although the Mac is reachable over the cable (cable plugged in later, or
    /// a USB drop-out forced Wi-Fi) → switch back. Not more often than once a minute if the cable
    /// attempt keeps failing.
    private func checkBackToCable() {
        guard case .connected = phase, let t = timing, !t.link.hasPrefix("USB"),
              Date().timeIntervalSince(lastCableFailure) > 60,
              let last = lastHostID, let h = discovered.first(where: { $0.hostID == last }),
              !h.cableInterfaces.isEmpty else { return }
        connect(h, reconnecting: true)
    }

    func isPaired(_ h: DiscoveredHost) -> Bool { paired.contains { $0.id == h.hostID } }

    /// From a Shortcut: connect to that Mac (or the last one) now, or as soon as Bonjour finds it.
    func requestConnect(hostID: String?) {
        guard let target = hostID ?? lastHostID else { return }
        switch phase {
        case .connected, .connecting, .reconnecting:
            if hostID == nil || lastHostID == target { return }   // already there
            disconnectQuietly()
        case .failed:
            phase = .idle
        case .idle:
            break
        }
        lastHostID = target
        if let h = discovered.first(where: { $0.hostID == target }) { connect(h) }   // else autoConnect() on discovery
    }

    private func disconnectQuietly() {
        let s = session
        session = nil
        s?.close()
        phase = .idle
    }

    /// Back from the background (or the iPad unlocked): iOS may have killed the connection
    /// meanwhile. A failed attempt gets a fresh try; a live one asks for a keyframe so the
    /// picture is complete again at once.
    private func cameToForeground() {
        switch phase {
        case .failed:
            guard lastHostID != nil else { return }
            phase = .idle
            autoConnect()
        case .idle:
            autoConnect()
        case .connected:
            renderer.requestKeyframe?()
        default:
            break
        }
    }

    private func autoConnect() {
        guard phase == .idle, let last = lastHostID,
              let h = discovered.first(where: { $0.hostID == last }) else { return }
        connect(h)
    }

    // MARK: Pairing

    func pair(with host: DiscoveredHost, code raw: String) {
        guard let code = PairingCode.normalize(raw) else {
            pairingError = PairingError.badCode.errorDescription
            return
        }
        pairingBusy = true
        pairingError = nil
        let attempt = PairingAttempt()
        pairingAttempt = attempt
        attempt.run(endpoint: host.endpoint, code: code, deviceID: deviceID, deviceName: deviceName) { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                self.pairingBusy = false
                self.pairingAttempt = nil
                switch result {
                case .success(let grant):
                    guard let key = Data(base64Encoded: grant.keyBase64), key.count == 32 else {
                        self.pairingError = L("Ungültiger Schlüssel vom Mac.")
                        return
                    }
                    Keychain.set(key, account: "host-\(grant.hostID)")
                    self.paired.removeAll { $0.id == grant.hostID }
                    self.paired.append(PairedHost(id: grant.hostID, name: grant.hostName, fingerprint: HostKey.fingerprint(key)))
                    self.save(self.paired, "pairedHosts")
                    self.lastHostID = grant.hostID
                    if let h = self.discovered.first(where: { $0.hostID == grant.hostID }) { self.connect(h) }
                case .failure(let e):
                    self.pairingError = e.localizedDescription
                }
            }
        }
    }

    func forget(_ host: PairedHost) {
        if hostInfo?.hostID == host.id { disconnect() }
        Keychain.delete(account: "host-\(host.id)")
        paired.removeAll { $0.id == host.id }
        save(paired, "pairedHosts")
        if lastHostID == host.id { lastHostID = nil }
    }

    // MARK: Session

    func connect(_ host: DiscoveredHost, reconnecting: Bool = false) {
        guard let key = Keychain.get(account: "host-\(host.hostID)") else {
            phase = .failed(L("Dieser Mac ist nicht gekoppelt."))
            return
        }
        let old = session
        session = nil
        old?.close()
        if reconnecting {
            renderer.reset(keepImage: true)
            phase = .reconnecting(host.name)
        } else {
            reconnectDeadline = nil
            renderer.reset()
            videoSize = .zero
            phase = .connecting(host.name)
        }
        let s = Session(endpoint: host.endpoint, key: key, deviceID: deviceID, deviceName: deviceName, renderer: renderer,
                        audioPlayer: audioPlayer)
        s.cableInterfaces = host.cableInterfaces
        s.peerToPeer = peerToPeer
        s.onCableFallback = { [weak self] in Task { @MainActor in self?.lastCableFailure = Date() } }
        s.onConnected = { [weak self] in
            Task { @MainActor in
                self?.reconnectDeadline = nil
                self?.phase = .connected(host.name)
                self?.lastHostID = host.hostID
                self?.sendSettingsSnapshot()
            }
        }
        s.onHostInfo = { [weak self] info in Task { @MainActor in self?.hostInfo = info; self?.secondary = info.secondary == true } }
        s.onAppInfo = { [weak self] app in Task { @MainActor in self?.frontApp = app } }
        s.onSourceList = { [weak self] l in Task { @MainActor in self?.sourceList = l } }
        s.onPluginActions = { [weak self] l in Task { @MainActor in self?.pluginActions = l } }
        s.onToast = { [weak self] t in Task { @MainActor in self?.show(t) } }
        s.onClipboard = { [weak self] c in Task { @MainActor in self?.receiveClipboard(c) } }
        let palette = self.palette
        palette.image = nil
        s.onPalette = { palette.receive($0) }
        s.onScreenshot = { [weak self] d in
            Task { @MainActor in
                guard let self else { return }
                self.screenshotPending = false
                if let img = UIImage(data: d) { self.screenshot = img }
                else { self.show(Toast(text: L("Bildschirmfoto fehlgeschlagen – fehlt am Mac die Bildschirmaufnahme-Erlaubnis?"), seconds: 2.5)) }
            }
        }
        s.onSettingsPatch = { [weak self] patch in Task { @MainActor in self?.applySettingsPatch(patch) } }
        s.onTiming = { [weak self] t in
            Task { @MainActor in
                guard let self else { return }
                let linkChanged = self.timing?.link != t.link
                self.timing = t
                if linkChanged { self.sendConfig() }
            }
        }
        s.onClosed = { [weak self, weak s] reason in
            Task { @MainActor in
                guard let self, self.session === s else { return }
                self.session = nil
                self.hostInfo = nil
                self.timing = nil
                self.sourceList = nil
                self.pluginActions = []
                self.secondary = false
                self.handleClosed(host: host, reason: reason)
            }
        }
        session = s
        s.start()
        sendConfig()
    }

    /// A running session ended without the user asking: keep the picture and reconnect for up
    /// to 30 s (USB drop-outs last ~3 s; Wi-Fi is the fallback meanwhile).
    private func handleClosed(host: DiscoveredHost, reason: String?) {
        let wasLive: Bool
        switch phase {
        case .connected, .reconnecting: wasLive = true
        default: wasLive = false
        }
        guard wasLive, lastHostID == host.hostID else {
            phase = reason.map { .failed($0) } ?? .idle
            return
        }
        let deadline = reconnectDeadline ?? Date().addingTimeInterval(30)
        reconnectDeadline = deadline
        guard Date() < deadline else {
            reconnectDeadline = nil
            renderer.reset()
            videoSize = .zero
            phase = .failed(reason ?? L("Verbindung verloren."))
            return
        }
        phase = .reconnecting(host.name)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self, case .reconnecting = self.phase, self.session == nil else { return }
            // Fresh browse result: the cable interface may have been re-created.
            let h = self.discovered.first(where: { $0.hostID == host.hostID }) ?? host
            self.connect(h, reconnecting: true)
        }
    }

    func disconnect() {
        let s = session
        session = nil
        s?.close()
        hostInfo = nil
        timing = nil
        lastHostID = nil   // no auto-reconnect after an explicit disconnect
        reconnectDeadline = nil
        phase = .idle
    }

    func retry() {
        phase = .idle
        if let last = lastHostID, let h = discovered.first(where: { $0.hostID == last }) { connect(h) }
    }

    /// Called by the canvas whenever its pixel size changes (rotation, first layout).
    func updateViewPixelSize(width: Int, height: Int) {
        guard (width, height) != viewPixelSize, width > 0, height > 0 else { return }
        viewPixelSize = (width, height)
        sendConfig()
    }

    private func sendConfig() {
        guard let session, viewPixelSize.0 > 0 else { return }
        let b = battery
        session.send(config: ClientConfig(viewPixelWidth: viewPixelSize.0, viewPixelHeight: viewPixelSize.1, quality: effectiveQuality,
                                          diagnostics: diagnostics, batteryLevel: b.level, batteryCharging: b.charging,
                                          tabletMode: tabletModeActive, laser: laserMode && !settings.viewOnly))
    }

    // MARK: Developer API (settings live on the iPad; the Mac reads and patches them)

    private func sendSettingsSnapshot() {
        session?.send(settings: settings, quality: quality)
    }

    /// Patch from the Mac's developer API: {settings?, quality?, removeAppProfiles?}.
    func applySettingsPatch(_ patch: [String: Any]) {
        var s = settings
        if let sp = patch["settings"] as? [String: Any], let merged = applyPatch(s, sp) { s = merged }
        for id in patch["removeAppProfiles"] as? [String] ?? [] {
            s.appShortcutBars[id] = nil
            s.appPenProfiles[id] = nil
            s.appNames[id] = nil
        }
        if s != settings { settings = s }
        if let qp = patch["quality"] as? [String: Any], let q = applyPatch(quality, qp), q != quality { quality = q }
    }

    func report(_ gesture: GestureEvent) { session?.send(gesture) }

    func selectSource(_ sel: SourceSelection) { session?.send(sel) }

    // MARK: Tablet presets

    func saveTabletPreset(named name: String) {
        let n = name.trimmingCharacters(in: .whitespaces)
        let preset = TabletPreset(name: n.isEmpty ? L("Bereich %d", settings.tabletPresets.count + 1) : n,
                                  area: tabletArea, lockAspect: tabletLock)
        // Same name again replaces the old one.
        if let i = settings.tabletPresets.firstIndex(where: { $0.name == preset.name }) {
            settings.tabletPresets[i].area = preset.area
            settings.tabletPresets[i].lockAspect = preset.lockAspect
        } else {
            settings.tabletPresets.append(preset)
        }
    }

    /// "Full area" first, then the saved presets.
    var allTabletPresets: [TabletPreset] { [TabletPreset.fullArea] + settings.tabletPresets }

    /// App-bound preset in use right now (the app in front on the Mac has one).
    var activeAppPreset: TabletPreset? { settings.tabletPreset(for: frontApp?.bundleID) }
    /// The area in use right now (app-bound preset or the normal area).
    var tabletArea: TabletArea { effectiveSettings.tabletArea }
    var tabletLock: Bool { effectiveSettings.tabletLockAspect }

    /// Changes the area in use: the app-bound preset while its app is in front, else the normal area.
    func setTabletArea(_ a: TabletArea) {
        if let p = activeAppPreset, let i = settings.tabletPresets.firstIndex(where: { $0.id == p.id }) {
            settings.tabletPresets[i].area = a
        } else {
            settings.tabletArea = a
        }
    }

    func setTabletLock(_ on: Bool) {
        if let p = activeAppPreset, let i = settings.tabletPresets.firstIndex(where: { $0.id == p.id }) {
            settings.tabletPresets[i].lockAspect = on
        } else {
            settings.tabletLockAspect = on
        }
    }

    /// Binds a preset to the app in front (or unbinds it). One preset per app.
    func bindTabletPreset(_ p: TabletPreset, toFrontApp: Bool) {
        guard let i = settings.tabletPresets.firstIndex(where: { $0.id == p.id }) else { return }
        if toFrontApp, let app = frontApp {
            for j in settings.tabletPresets.indices where settings.tabletPresets[j].appBundleID == app.bundleID {
                settings.tabletPresets[j].appBundleID = nil; settings.tabletPresets[j].appName = nil
            }
            settings.tabletPresets[i].appBundleID = app.bundleID
            settings.tabletPresets[i].appName = app.name
        } else {
            settings.tabletPresets[i].appBundleID = nil
            settings.tabletPresets[i].appName = nil
        }
    }

    func applyTabletPreset(_ p: TabletPreset) {
        setTabletLock(p.lockAspect)
        setTabletArea(p.area)
    }

    /// Toggles game mode for the app in front on the Mac.
    func toggleGameMode() {
        guard let app = frontApp else { return }
        if settings.gameApps[app.bundleID] == nil { settings.gameApps[app.bundleID] = app.name } else { settings.gameApps[app.bundleID] = nil }
        sendConfig()
    }

    func hold(_ key: HoldKey, down: Bool) {
        guard !settings.viewOnly || !down else { return }
        session?.send(KeyEvent(hidUsage: key.rawValue, down: down))
    }

    func show(_ t: Toast) {
        toast = t
        toastHide?.cancel()
        let w = DispatchWorkItem { [weak self] in self?.toast = nil }
        toastHide = w
        DispatchQueue.main.asyncAfter(deadline: .now() + t.seconds, execute: w)
    }

    // MARK: Clipboard (only on request, never automatic)

    /// Sends the iPad clipboard (image or text) to the Mac clipboard.
    func copyClipboardToMac() {
        guard let session else { return }
        let pb = UIPasteboard.general
        if pb.hasImages, let img = pb.image, let png = img.pngData(), png.count <= ClipboardItem.maxBytes {
            session.send(clipboard: ClipboardItem(kind: .png, data: png))
            show(Toast(text: L("Bild in die Mac-Zwischenablage kopiert"), seconds: 1.6))
        } else if pb.hasStrings, let t = pb.string, !t.isEmpty {
            session.send(clipboard: .text(t))
            show(Toast(text: L("Text in die Mac-Zwischenablage kopiert"), seconds: 1.6))
        } else {
            show(Toast(text: L("Die iPad-Zwischenablage ist leer"), seconds: 1.6))
        }
    }

    /// Asks the Mac for a full-resolution picture of what is streamed.
    func pickPalette() {
        session?.sendPalette(.pick)
        show(Toast(text: L("Am Mac den Bereich für die Palette aufziehen (Esc bricht ab)"), seconds: 3))
    }

    func removePalette() {
        session?.sendPalette(.remove)
        palette.image = nil
    }

    func palettePointer(_ m: MouseEvent) { session?.sendPalette(m) }

    func requestScreenshot() {
        guard let session else { return }
        screenshotPending = true
        session.requestScreenshot()
    }

    /// Asks the Mac for its clipboard; the answer lands in `receiveClipboard`.
    func fetchClipboardFromMac() { session?.requestClipboard() }

    private func receiveClipboard(_ c: ClipboardItem) {
        switch c.kind {
        case .text:
            guard let t = c.text else { return }
            UIPasteboard.general.string = t
            show(Toast(text: L("Text vom Mac – jetzt auf dem iPad einsetzbar"), seconds: 1.8))
        case .png:
            guard let img = UIImage(data: c.data) else { return }
            UIPasteboard.general.image = img
            show(Toast(text: L("Bild vom Mac – jetzt auf dem iPad einsetzbar"), seconds: 1.8))
        case .empty:
            show(Toast(text: L("Die Mac-Zwischenablage ist leer"), seconds: 1.6))
        }
    }

    func runPlugin(_ id: String) { guard !settings.viewOnly else { return }; session?.runPluginAction(id) }

    /// Runs a bar / radial menu button: its plugin action, or its shortcut.
    func run(_ b: ShortcutButton) {
        guard !settings.viewOnly else { return }
        if let t = b.tool { runTool(t) } else if let p = b.pluginAction { runPlugin(p) } else { session?.send(b.shortcut) }
    }

    /// Toggles an iPad tool (from a Pencil gesture, the radial menu, a bar button or a Shortcut).
    func runTool(_ t: IPadTool) {
        func toggleGuide(_ g: DrawingGuide) {
            guide = guide == g ? .none : g
            show(Toast(text: guide == .none ? L("%@ aus", t.title) : t.title, seconds: 1.2))
        }
        switch t {
        case .ruler: toggleGuide(.ruler)
        case .perspective1: toggleGuide(.perspective(1))
        case .perspective2: toggleGuide(.perspective(2))
        case .perspective3: toggleGuide(.perspective(3))
        case .ellipse: toggleGuide(.ellipse)
        case .shapeRecognition:
            settings.shapeRecognition.toggle()
            show(Toast(text: settings.shapeRecognition ? L("Formerkennung an – am Strichende kurz halten") : L("%@ aus", t.title), seconds: 1.6))
        case .laser:
            laserMode.toggle()
            show(Toast(text: laserMode ? L("Laserpointer an – der Pencil zeichnet nur noch Leuchtspuren") : L("Laserpointer aus"), seconds: 1.6))
        case .screenshot:
            requestScreenshot()
        case .palette:
            if palette.image != nil { removePalette() } else { pickPalette() }
        case .mirror:
            mirrored.toggle()
            show(Toast(text: mirrored ? L("Gespiegelt – nur auf dem iPad, der Mac bleibt wie er ist") : L("%@ aus", t.title), seconds: 1.8))
        }
    }

    func trigger(_ action: PencilAction) {
        guard !settings.viewOnly else { return }
        if action == .radialMenu { return }   // opened by the canvas, which knows the Pencil position
        if case .plugin(let id) = action { runPlugin(id); return }
        if case .tool(let t) = action { runTool(t); return }
        guard let s = action.shortcut else { return }
        session?.send(s)
    }

    // MARK: Persistence

    private func save<T: Encodable>(_ v: T, _ key: String) {
        if let d = try? JSONEncoder().encode(v) { UserDefaults.standard.set(d, forKey: key) }
    }

    private static func load<T: Decodable>(_ t: T.Type, _ key: String) -> T? {
        guard let d = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(t, from: d)
    }
}
