import Foundation
import Network
import TafelKit

/// Two Bonjour listeners:
///  - `_tafel._tcp`: regular sessions, TLS-PSK with the long-term host key.
///  - `_tafelpair._tcp`: only while the user has opened the pairing window, TLS-PSK derived from
///    the one-time code. Hands out the host key once, then closes.
/// One iPad session at a time: a control connection (input, timing) and a video connection, so
/// video bursts never delay Pencil packets behind them (no head-of-line blocking).
final class HostServer {
    let queue = DispatchQueue(label: "tafel.host.net", qos: .userInteractive)

    var hostID = ""
    var hostName = ""
    /// Bonjour advertisement; disabled in integration tests.
    var advertise = true
    /// Also listen/advertise on Äbbl peer-to-peer Wi-Fi (AWDL). Off by default: AWDL costs
    /// Wi-Fi latency. Only needed when Mac and iPad share no network and no cable.
    var peerToPeer = false
    var sourceDescription: () -> String = { "" }

    // Callbacks, invoked on `queue`.
    var onClientConfig: ((ClientConfig) -> Void)?
    var onPen: ((PenSample) -> Void)?
    var onScroll: ((ScrollEvent) -> Void)?
    var onShortcut: ((Shortcut) -> Void)?
    var onKey: ((KeyEvent) -> Void)?
    var onMouse: ((MouseEvent) -> Void)?
    var onText: ((String) -> Void)?
    var onRequestKeyframe: (() -> Void)?
    var onVideoConnected: (() -> Void)?
    /// Device name (nil = session ended) and the path it uses ("USB-Kabel (en8)", …).
    var onSession: ((String?, String) -> Void)?
    var onPaired: ((String) -> Void)?
    var onStatus: ((String) -> Void)?
    /// Listener ready (true) or not (false) – a state, independent of the shown language.
    var onReady: ((Bool) -> Void)?

    private var listener: NWListener?
    private var pairingListener: NWListener?
    private var pending: [ObjectIdentifier: FramedConnection] = [:]
    private var control: FramedConnection?
    private var sessionDeviceID: String?

    private let videoLock = NSLock()
    private var video: FramedConnection?
    private var audio: FramedConnection?

    // MARK: Main listener

    func start(key: Data) {
        queue.async { [self] in
            listener?.cancel()
            do {
                let l = try NWListener(using: TafelNetwork.parameters(psk: key, identity: HostKey.pskIdentity, channel: .control,
                                                                    link: peerToPeer ? .any : .noPeerToPeer))
                if advertise {
                    l.service = NWListener.Service(name: hostName, type: TafelNetwork.serviceType,
                                                   txtRecord: NWTXTRecord([TafelNetwork.txtHostIDKey: hostID]))
                }
                l.stateUpdateHandler = { [weak self] state in
                    switch state {
                    case .ready:
                        self?.onReady?(true)
                        self?.onStatus?(L("Bereit (Port %d)", Int(l.port?.rawValue ?? 0)))
                    case .failed(let e):
                        self?.onReady?(false)
                        self?.onStatus?(L("Listener-Fehler: %@", e.localizedDescription))
                    case .waiting(let e):
                        self?.onReady?(false)
                        self?.onStatus?(L("Wartet: %@", e.localizedDescription))
                    default: break
                    }
                }
                l.newConnectionHandler = { [weak self] c in self?.accept(c) }
                l.start(queue: queue)
                listener = l
            } catch {
                onStatus?(L("Listener konnte nicht starten: %@", error.localizedDescription))
            }
        }
    }

    /// Drop the current session (e.g. after unpairing).
    func disconnectSession() {
        queue.async { [self] in
            control?.cancel()
            currentVideo()?.cancel()
            currentAudio()?.cancel()
        }
    }

    private func accept(_ c: NWConnection) {
        let fc = FramedConnection(c, queue: queue)
        let id = ObjectIdentifier(fc)
        pending[id] = fc
        fc.onFrame = { [weak self, weak fc] frame in
            guard let self, let fc else { return }
            guard frame.type == .hello, let hello = try? JSONWire.decode(Hello.self, frame.payload) else {
                fc.cancel(); return
            }
            self.pending[id] = nil
            self.promote(fc, hello: hello)
        }
        fc.onClose = { [weak self] _ in self?.pending[id] = nil }
        fc.start()
        // Connections that never say hello are dropped.
        queue.asyncAfter(deadline: .now() + 5) { [weak self, weak fc] in
            guard let self, let fc, self.pending[id] != nil else { return }
            self.pending[id] = nil
            fc.cancel()
        }
    }

    private func promote(_ fc: FramedConnection, hello: Hello) {
        guard hello.protocolVersion == tafelProtocolVersion else {
            fc.sendJSON(.error, ErrorMessage(message: L("Protokollversion %d wird nicht unterstützt (Mac: %d). Bitte beide Apps aktualisieren.", Int(hello.protocolVersion), Int(tafelProtocolVersion))))
            queue.asyncAfter(deadline: .now() + 0.5) { fc.cancel() }
            return
        }
        switch hello.role {
        case .control:
            if let old = control, old !== fc { old.onClose = nil; old.cancel(); currentVideo()?.cancel(); currentAudio()?.cancel() }
            control = fc
            sessionDeviceID = hello.deviceID
            fc.onFrame = { [weak self] f in self?.handleControl(f, from: fc) }
            fc.onClose = { [weak self, weak fc] _ in
                guard let self, self.control === fc else { return }
                self.control = nil
                self.sessionDeviceID = nil
                self.currentVideo()?.cancel()
                self.currentAudio()?.cancel()
                self.onSession?(nil, "")
            }
            fc.sendJSON(.hostInfo, HostInfo(hostID: hostID, hostName: hostName, sourceDescription: sourceDescription()))
            onSession?(hello.deviceName, fc.connection.linkDescription)
        case .video:
            guard hello.deviceID == sessionDeviceID else { fc.cancel(); return }
            let old: FramedConnection? = videoLock.withLock { let o = video; video = fc; return o }
            if let old, old !== fc { old.onClose = nil; old.cancel() }
            fc.onFrame = { [weak self] f in if f.type == .requestKeyframe { self?.onRequestKeyframe?() } }
            fc.onClose = { [weak self, weak fc] _ in
                guard let self else { return }
                self.videoLock.withLock { if self.video === fc { self.video = nil } }
            }
            onVideoConnected?()
        case .audio:
            guard hello.deviceID == sessionDeviceID else { fc.cancel(); return }
            let old: FramedConnection? = videoLock.withLock { let o = audio; audio = fc; return o }
            if let old, old !== fc { old.onClose = nil; old.cancel() }
            fc.onFrame = { _ in }
            fc.onClose = { [weak self, weak fc] _ in
                guard let self else { return }
                self.videoLock.withLock { if self.audio === fc { self.audio = nil } }
            }
        case .pair:
            fc.cancel() // pairing only on the pairing listener
        }
    }

    private func handleControl(_ f: Frame, from fc: FramedConnection) {
        switch f.type {
        case .pen:
            if let s = try? PenSample(decoding: f.payload) { onPen?(s) }
        case .scroll:
            if let s = try? ScrollEvent(decoding: f.payload) { onScroll?(s) }
        case .shortcut:
            if let s = try? Shortcut(decoding: f.payload) { onShortcut?(s) }
        case .mouse:
            if let m = try? MouseEvent(decoding: f.payload) { onMouse?(m) }
        case .key:
            if let k = try? KeyEvent(decoding: f.payload) { onKey?(k) }
        case .text:
            if let t = try? TextInput(decoding: f.payload) { onText?(t.text) }
        case .ping:
            if let p = try? Ping(decoding: f.payload) {
                fc.send(.pong, Pong(clientTime: p.clientTime, hostTime: Date().timeIntervalSince1970).encoded())
            }
        case .clientConfig:
            if let c = try? JSONWire.decode(ClientConfig.self, f.payload) { onClientConfig?(c) }
        case .requestKeyframe:
            onRequestKeyframe?()
        default:
            break
        }
    }

    func sendHostInfo() {
        queue.async { [self] in
            control?.sendJSON(.hostInfo, HostInfo(hostID: hostID, hostName: hostName, sourceDescription: sourceDescription()))
        }
    }

    // MARK: Video

    private func currentVideo() -> FramedConnection? { videoLock.withLock { video } }

    var hasVideo: Bool { currentVideo() != nil }
    var videoBacklog: Int { currentVideo()?.pendingBytes ?? 0 }

    /// Thread-safe; called from the encoder callback.
    func sendVideo(format: VideoFormat?, frame: VideoFrame) {
        guard let v = currentVideo() else { return }
        if let format { v.send(.videoFormat, format.encoded()) }
        v.send(.videoFrame, frame.encoded())
    }

    // MARK: Audio

    private func currentAudio() -> FramedConnection? { videoLock.withLock { audio } }

    /// Thread-safe. Drops chunks while more than ~80 ms of audio are still queued on the socket,
    /// so a network hiccup costs a short gap instead of a growing delay.
    func sendAudio(_ chunk: AudioChunk) {
        guard let a = currentAudio() else { return }
        let maxBacklog = chunk.sampleRate * chunk.channels * 2 * 80 / 1000
        guard a.pendingBytes < maxBacklog else { return }
        a.send(.audioChunk, chunk.encoded())
    }

    var mainPort: UInt16? { queue.sync { listener?.port?.rawValue } }
    var pairingPort: UInt16? { queue.sync { pairingListener?.port?.rawValue } }

    // MARK: Pairing

    func startPairing(code: String, hostKey: Data) {
        queue.async { [self] in
            pairingListener?.cancel()
            do {
                let params = TafelNetwork.parameters(psk: PairingCode.pairingPSK(code: code), identity: PairingCode.pskIdentity,
                                                    channel: .control, link: peerToPeer ? .any : .noPeerToPeer)
                let l = try NWListener(using: params)
                if advertise {
                    l.service = NWListener.Service(name: hostName, type: TafelNetwork.pairingServiceType,
                                                   txtRecord: NWTXTRecord([TafelNetwork.txtHostIDKey: hostID]))
                }
                l.newConnectionHandler = { [weak self] c in self?.acceptPairing(c, hostKey: hostKey) }
                l.start(queue: queue)
                pairingListener = l
            } catch {
                onStatus?(L("Kopplung konnte nicht starten: %@", error.localizedDescription))
            }
        }
    }

    func stopPairing() {
        queue.async { [self] in
            pairingListener?.cancel()
            pairingListener = nil
        }
    }

    private func acceptPairing(_ c: NWConnection, hostKey: Data) {
        let fc = FramedConnection(c, queue: queue)
        let id = ObjectIdentifier(fc)
        pending[id] = fc
        fc.onFrame = { [weak self, weak fc] frame in
            guard let self, let fc else { return }
            // Reaching this point means the TLS handshake with the code-derived key succeeded.
            guard frame.type == .hello, let hello = try? JSONWire.decode(Hello.self, frame.payload), hello.role == .pair else {
                fc.cancel(); return
            }
            fc.sendJSON(.pairGrant, PairGrant(hostID: self.hostID, hostName: self.hostName, keyBase64: hostKey.base64EncodedString()))
            self.pairingListener?.cancel()
            self.pairingListener = nil
            self.onPaired?(hello.deviceName)
            self.queue.asyncAfter(deadline: .now() + 2) { fc.cancel(); self.pending[id] = nil }
        }
        fc.onClose = { [weak self] _ in self?.pending[id] = nil }
        fc.start()
    }
}
