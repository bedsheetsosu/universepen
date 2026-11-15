import Foundation

public let tafelProtocolVersion = 2

/// One byte message tag. Low-frequency messages are JSON, high-frequency ones binary.
public enum MessageType: UInt8, Sendable {
    // JSON
    case hello = 0x01          // client -> host, first frame on every connection
    case hostInfo = 0x02       // host -> client
    case clientConfig = 0x03   // client -> host
    case pairGrant = 0x04      // host -> client, only on the pairing listener
    case error = 0x05          // host -> client
    // binary input
    case pen = 0x10
    case scroll = 0x11
    case mouse = 0x12          // trackpad / mouse pointer
    case shortcut = 0x20
    case key = 0x21            // hardware keyboard key down/up (HID usage)
    case text = 0x22           // on-screen keyboard text (UTF-8)
    // timing
    case ping = 0x30
    case pong = 0x31
    // video
    case videoFormat = 0x40
    case videoFrame = 0x41
    case requestKeyframe = 0x42
    // audio
    case audioChunk = 0x50
}

public struct Frame: Sendable {
    public var type: MessageType
    public var payload: Data
    public init(type: MessageType, payload: Data) {
        self.type = type
        self.payload = payload
    }
}

/// `[u8 type][u32 LE length][payload]`
public enum FrameCodec {
    public static let headerSize = 5
    public static let maxPayload = 64 * 1024 * 1024

    public static func encode(_ type: MessageType, _ payload: Data) -> Data {
        var w = ByteWriter(capacity: headerSize + payload.count)
        w.u8(type.rawValue)
        w.u32(UInt32(payload.count))
        w.rest(payload)
        return w.data
    }

    /// Returns raw type byte and payload length.
    public static func parseHeader(_ header: Data) throws -> (type: UInt8, length: Int) {
        var r = ByteReader(header)
        let t = try r.u8()
        let n = Int(try r.u32())
        guard n <= maxPayload else { throw WireError.tooLarge }
        return (t, n)
    }

    /// Splits a byte stream into frames; returns frames and the unconsumed tail. Used by tests
    /// and as a reference for the streaming receiver.
    public static func split(_ stream: Data) throws -> (frames: [Frame], rest: Data) {
        var frames: [Frame] = []
        var cursor = stream.startIndex
        while stream.endIndex - cursor >= headerSize {
            let (t, n) = try parseHeader(Data(stream[cursor..<(cursor + headerSize)]))
            guard stream.endIndex - cursor - headerSize >= n else { break }
            let start = cursor + headerSize
            if let type = MessageType(rawValue: t) {
                frames.append(Frame(type: type, payload: Data(stream[start..<(start + n)])))
            }
            cursor = start + n
        }
        return (frames, Data(stream[cursor..<stream.endIndex]))
    }
}

// MARK: - JSON messages

public enum ConnectionRole: String, Codable, Sendable {
    case control, video, audio, pair
}

public struct Hello: Codable, Equatable, Sendable {
    public var protocolVersion: Int
    public var role: ConnectionRole
    public var deviceID: String
    public var deviceName: String
    public init(protocolVersion: Int = tafelProtocolVersion, role: ConnectionRole, deviceID: String, deviceName: String) {
        self.protocolVersion = protocolVersion
        self.role = role
        self.deviceID = deviceID
        self.deviceName = deviceName
    }
}

public struct HostInfo: Codable, Equatable, Sendable {
    public var hostID: String
    public var hostName: String
    public var protocolVersion: Int
    /// Human-readable description of what is being captured.
    public var sourceDescription: String
    public init(hostID: String, hostName: String, protocolVersion: Int = tafelProtocolVersion, sourceDescription: String) {
        self.hostID = hostID
        self.hostName = hostName
        self.protocolVersion = protocolVersion
        self.sourceDescription = sourceDescription
    }
}

public enum VideoCodec: String, Codable, CaseIterable, Sendable {
    case h264, hevc
}

public struct StreamQuality: Codable, Equatable, Sendable {
    public var codec: VideoCodec
    public var bitrateMbps: Double
    public var fps: Int
    /// 1.0 = native iPad pixels, 0.5 = half resolution per axis.
    public var resolutionScale: Double
    /// Also capture and send the Mac's sound.
    public var audio: Bool

    public init(codec: VideoCodec = .h264, bitrateMbps: Double = 30, fps: Int = 60, resolutionScale: Double = 1.0, audio: Bool = true) {
        self.codec = codec
        self.bitrateMbps = bitrateMbps
        self.fps = fps
        self.resolutionScale = resolutionScale
        self.audio = audio
    }

    private enum CodingKeys: String, CodingKey { case codec, bitrateMbps, fps, resolutionScale, audio }

    /// Tolerates settings saved by older versions (missing keys get defaults).
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = StreamQuality()
        codec = try c.decodeIfPresent(VideoCodec.self, forKey: .codec) ?? d.codec
        bitrateMbps = try c.decodeIfPresent(Double.self, forKey: .bitrateMbps) ?? d.bitrateMbps
        fps = try c.decodeIfPresent(Int.self, forKey: .fps) ?? d.fps
        resolutionScale = try c.decodeIfPresent(Double.self, forKey: .resolutionScale) ?? d.resolutionScale
        audio = try c.decodeIfPresent(Bool.self, forKey: .audio) ?? d.audio
    }
}

public struct ClientConfig: Codable, Equatable, Sendable {
    /// Drawable area of the iPad in physical pixels (full screen, current orientation).
    public var viewPixelWidth: Int
    public var viewPixelHeight: Int
    public var quality: StreamQuality
    /// Free-text network diagnostics from the iPad (interfaces it can see). Shown/logged on the
    /// Mac; never affects streaming.
    public var diagnostics: String?

    public init(viewPixelWidth: Int, viewPixelHeight: Int, quality: StreamQuality, diagnostics: String? = nil) {
        self.viewPixelWidth = viewPixelWidth
        self.viewPixelHeight = viewPixelHeight
        self.quality = quality
        self.diagnostics = diagnostics
    }

    /// Same config, ignoring diagnostics (decides whether the stream must restart).
    public func sameStream(as other: ClientConfig?) -> Bool {
        guard let other else { return false }
        return viewPixelWidth == other.viewPixelWidth && viewPixelHeight == other.viewPixelHeight && quality == other.quality
    }
}

public struct PairGrant: Codable, Equatable, Sendable {
    public var hostID: String
    public var hostName: String
    /// Base64 of the 32-byte long-term host key used as TLS PSK for regular connections.
    public var keyBase64: String
    public init(hostID: String, hostName: String, keyBase64: String) {
        self.hostID = hostID
        self.hostName = hostName
        self.keyBase64 = keyBase64
    }
}

public struct ErrorMessage: Codable, Equatable, Sendable {
    public var message: String
    public init(message: String) { self.message = message }
}

public enum JSONWire {
    public static func encode<T: Encodable>(_ v: T) throws -> Data { try JSONEncoder().encode(v) }
    public static func decode<T: Decodable>(_ t: T.Type, _ d: Data) throws -> T { try JSONDecoder().decode(t, from: d) }
}

// MARK: - Binary input messages

/// Trackpad or mouse on the iPad, acting as the Mac's mouse. Position is absolute (where the
/// iPad pointer is over the mirrored image), so pointer and picture always line up.
public struct MouseEvent: Equatable, Sendable {
    public enum Phase: UInt8, Sendable { case move = 0, down = 1, up = 2, exit = 3 }
    public enum Button: UInt8, Sendable { case left = 0, right = 1 }

    public var phase: Phase
    public var button: Button
    public var x: Float
    public var y: Float

    public init(phase: Phase, button: Button = .left, x: Float, y: Float) {
        self.phase = phase; self.button = button; self.x = x; self.y = y
    }

    public func encoded() -> Data {
        var w = ByteWriter(capacity: 10)
        w.u8(phase.rawValue); w.u8(button.rawValue); w.f32(x); w.f32(y)
        return w.data
    }

    public init(decoding d: Data) throws {
        var r = ByteReader(d)
        guard let p = Phase(rawValue: try r.u8()) else { throw WireError.unknownValue("mouse phase") }
        guard let b = Button(rawValue: try r.u8()) else { throw WireError.unknownValue("mouse button") }
        phase = p; button = b
        x = try r.f32(); y = try r.f32()
    }
}

public enum PenPhase: UInt8, Sendable {
    case hover = 0      // in range, not touching
    case down = 1
    case move = 2       // touching
    case up = 3
    case enter = 4      // proximity in
    case exit = 5       // proximity out
    case cancel = 6     // touch cancelled by the system: release without a click target guarantee
}

/// A single Pencil sample, already converted to tablet semantics on the iPad.
public struct PenSample: Equatable, Sendable {
    public var phase: PenPhase
    /// Normalized position inside the streamed image, 0...1, origin top-left.
    public var x: Float
    public var y: Float
    /// 0...1 after the pressure curve.
    public var pressure: Float
    /// -1...1 (Wacom-style tilt vector).
    public var tiltX: Float
    public var tiltY: Float
    /// Barrel rotation in degrees (Pencil Pro roll), 0 if unsupported.
    public var rotation: Float
    /// iPad uptime timestamp of the sample (seconds).
    public var timestamp: Double

    public init(phase: PenPhase, x: Float, y: Float, pressure: Float = 0, tiltX: Float = 0, tiltY: Float = 0, rotation: Float = 0, timestamp: Double = 0) {
        self.phase = phase
        self.x = x
        self.y = y
        self.pressure = pressure
        self.tiltX = tiltX
        self.tiltY = tiltY
        self.rotation = rotation
        self.timestamp = timestamp
    }

    public func encoded() -> Data {
        var w = ByteWriter(capacity: 33)
        w.u8(phase.rawValue)
        w.f32(x); w.f32(y); w.f32(pressure)
        w.f32(tiltX); w.f32(tiltY); w.f32(rotation)
        w.f64(timestamp)
        return w.data
    }

    public init(decoding d: Data) throws {
        var r = ByteReader(d)
        guard let p = PenPhase(rawValue: try r.u8()) else { throw WireError.unknownValue("pen phase") }
        phase = p
        x = try r.f32(); y = try r.f32(); pressure = try r.f32()
        tiltX = try r.f32(); tiltY = try r.f32(); rotation = try r.f32()
        timestamp = try r.f64()
    }
}

public struct ModifierSet: OptionSet, Codable, Hashable, Sendable {
    public let rawValue: UInt8
    public init(rawValue: UInt8) { self.rawValue = rawValue }
    public static let command = ModifierSet(rawValue: 1 << 0)
    public static let shift = ModifierSet(rawValue: 1 << 1)
    public static let option = ModifierSet(rawValue: 1 << 2)
    public static let control = ModifierSet(rawValue: 1 << 3)

    public var symbols: String {
        var s = ""
        if contains(.control) { s += "⌃" }
        if contains(.option) { s += "⌥" }
        if contains(.shift) { s += "⇧" }
        if contains(.command) { s += "⌘" }
        return s
    }
}

/// Two-finger scroll, optionally with modifiers (used for zoom-by-scroll).
public struct ScrollEvent: Equatable, Sendable {
    /// Anchor in normalized image coordinates (where the gesture happens).
    public var x: Float
    public var y: Float
    /// Delta in normalized image units (1.0 = full width / height of the capture).
    public var dx: Float
    public var dy: Float
    public var modifiers: ModifierSet

    public init(x: Float, y: Float, dx: Float, dy: Float, modifiers: ModifierSet = []) {
        self.x = x; self.y = y; self.dx = dx; self.dy = dy; self.modifiers = modifiers
    }

    public func encoded() -> Data {
        var w = ByteWriter(capacity: 17)
        w.f32(x); w.f32(y); w.f32(dx); w.f32(dy); w.u8(modifiers.rawValue)
        return w.data
    }

    public init(decoding d: Data) throws {
        var r = ByteReader(d)
        x = try r.f32(); y = try r.f32(); dx = try r.f32(); dy = try r.f32()
        modifiers = ModifierSet(rawValue: try r.u8())
    }
}

/// A keyboard shortcut described by the *character* it should produce (e.g. "z"), not by a
/// hardware key code, so the Mac can resolve it against its active keyboard layout
/// (QWERTZ vs. QWERTY). Special keys use names: esc, delete, tab, space, return, left, right, up, down.
public struct Shortcut: Codable, Hashable, Sendable {
    public var key: String
    public var modifiers: ModifierSet

    public init(_ key: String, _ modifiers: ModifierSet = []) {
        self.key = key.lowercased()
        self.modifiers = modifiers
    }

    public var display: String {
        let k: String
        switch key {
        case "esc": k = "esc"
        case "delete": k = "⌫"
        case "tab": k = "⇥"
        case "space": k = "Leertaste"
        case "return": k = "↩"
        case "left": k = "←"
        case "right": k = "→"
        case "up": k = "↑"
        case "down": k = "↓"
        default: k = key.uppercased()
        }
        return modifiers.symbols + k
    }

    public static let specialKeys: [String: UInt16] = [
        "return": 36, "tab": 48, "space": 49, "delete": 51, "esc": 53,
        "left": 123, "right": 124, "down": 125, "up": 126,
    ]

    public func encoded() -> Data {
        var w = ByteWriter(capacity: 8)
        w.u8(modifiers.rawValue)
        w.string(key)
        return w.data
    }

    public init(decoding d: Data) throws {
        var r = ByteReader(d)
        modifiers = ModifierSet(rawValue: try r.u8())
        key = try r.string()
    }
}

public struct Ping: Equatable, Sendable {
    public var clientTime: Double
    public init(clientTime: Double) { self.clientTime = clientTime }
    public func encoded() -> Data { var w = ByteWriter(); w.f64(clientTime); return w.data }
    public init(decoding d: Data) throws { var r = ByteReader(d); clientTime = try r.f64() }
}

public struct Pong: Equatable, Sendable {
    public var clientTime: Double
    public var hostTime: Double
    public init(clientTime: Double, hostTime: Double) { self.clientTime = clientTime; self.hostTime = hostTime }
    public func encoded() -> Data { var w = ByteWriter(); w.f64(clientTime); w.f64(hostTime); return w.data }
    public init(decoding d: Data) throws { var r = ByteReader(d); clientTime = try r.f64(); hostTime = try r.f64() }
}

// MARK: - Video

public struct VideoFormat: Equatable, Sendable {
    public var codec: VideoCodec
    public var width: Int
    public var height: Int
    /// H.264: [SPS, PPS]; HEVC: [VPS, SPS, PPS]. Raw NAL units without start codes.
    public var parameterSets: [Data]

    public init(codec: VideoCodec, width: Int, height: Int, parameterSets: [Data]) {
        self.codec = codec; self.width = width; self.height = height; self.parameterSets = parameterSets
    }

    public func encoded() -> Data {
        var w = ByteWriter()
        w.u8(codec == .h264 ? 0 : 1)
        w.u32(UInt32(width)); w.u32(UInt32(height))
        w.u8(UInt8(parameterSets.count))
        for p in parameterSets { w.blob(p) }
        return w.data
    }

    public init(decoding d: Data) throws {
        var r = ByteReader(d)
        switch try r.u8() {
        case 0: codec = .h264
        case 1: codec = .hevc
        default: throw WireError.unknownValue("codec")
        }
        width = Int(try r.u32()); height = Int(try r.u32())
        let n = Int(try r.u8())
        var sets: [Data] = []
        for _ in 0..<n { sets.append(try r.blob()) }
        parameterSets = sets
    }
}

public struct VideoFrame: Equatable, Sendable {
    public var isKeyframe: Bool
    /// Host wall clock (seconds since 1970) when the frame was captured.
    public var captureTime: Double
    /// AVCC/HVCC payload: NAL units with 4-byte big-endian length prefixes.
    public var data: Data

    public init(isKeyframe: Bool, captureTime: Double, data: Data) {
        self.isKeyframe = isKeyframe; self.captureTime = captureTime; self.data = data
    }

    public func encoded() -> Data {
        var w = ByteWriter(capacity: data.count + 9)
        w.bool(isKeyframe)
        w.f64(captureTime)
        w.rest(data)
        return w.data
    }

    public init(decoding d: Data) throws {
        var r = ByteReader(d)
        isKeyframe = try r.bool()
        captureTime = try r.f64()
        data = r.rest()
    }
}

/// Uncompressed PCM, signed 16-bit little-endian, interleaved. 48 kHz stereo is ~1.5 Mbit/s,
/// small next to the video, and needs no codec delay.
public struct AudioChunk: Equatable, Sendable {
    public var sampleRate: Int
    public var channels: Int
    /// Host wall clock (seconds since 1970) of the first sample.
    public var captureTime: Double
    public var samples: Data

    public init(sampleRate: Int, channels: Int, captureTime: Double, samples: Data) {
        self.sampleRate = sampleRate; self.channels = channels; self.captureTime = captureTime; self.samples = samples
    }

    public var frameCount: Int { channels > 0 ? samples.count / (2 * channels) : 0 }

    public func encoded() -> Data {
        var w = ByteWriter(capacity: samples.count + 14)
        w.u32(UInt32(sampleRate))
        w.u8(UInt8(channels))
        w.f64(captureTime)
        w.rest(samples)
        return w.data
    }

    public init(decoding d: Data) throws {
        var r = ByteReader(d)
        sampleRate = Int(try r.u32())
        channels = Int(try r.u8())
        guard (1...8).contains(channels), (8000...192_000).contains(sampleRate) else { throw WireError.unknownValue("audio format") }
        captureTime = try r.f64()
        samples = r.rest()
        guard samples.count % (2 * channels) == 0 else { throw WireError.truncated }
    }
}
