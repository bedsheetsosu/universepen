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
    @Published var timing: Session.Timing?
    @Published var videoSize: CGSize = .zero
    @Published var pairingBusy = false
    @Published var pairingError: String?
    /// First-run setup finished (shown again via Settings → "Einrichtung erneut starten").
    @Published var onboardingDone = UserDefaults.standard.bool(forKey: "onboardingDone") {
        didSet { UserDefaults.standard.set(onboardingDone, forKey: "onboardingDone") }
    }
    /// On-screen keyboard shown (hardware keyboards work without it).
    @Published var showKeyboard = false

    @Published var settings: InputSettings { didSet { save(settings, "inputSettings") } }
    @Published var quality: StreamQuality { didSet { save(quality, "quality"); sendConfig() } }
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
        settings = Self.load(InputSettings.self, "inputSettings") ?? InputSettings()
        quality = Self.load(StreamQuality.self, "quality") ?? StreamQuality()
        showStatusOverlay = d.bool(forKey: "showStatusOverlay")
        peerToPeer = d.bool(forKey: "peerToPeer")
        paired = Self.load([PairedHost].self, "pairedHosts") ?? []
        renderer.onSize = { [weak self] size in self?.videoSize = size }
        startWiredMonitor()
        startBrowsing()
        backToCableTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkBackToCable() }
        }
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
            }
        }
        s.onHostInfo = { [weak self] info in Task { @MainActor in self?.hostInfo = info } }
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
        session.send(config: ClientConfig(viewPixelWidth: viewPixelSize.0, viewPixelHeight: viewPixelSize.1, quality: quality,
                                          diagnostics: diagnostics))
    }

    func trigger(_ action: PencilAction) {
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
