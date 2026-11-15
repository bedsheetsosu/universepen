import Foundation

/// What a Pencil gesture (double tap, squeeze) or a finger tap triggers.
public enum PencilAction: Codable, Hashable, Sendable {
    case none
    case shortcut(Shortcut)

    public static let undo = PencilAction.shortcut(Shortcut("z", .command))
    public static let redo = PencilAction.shortcut(Shortcut("z", [.command, .shift]))
    /// Affinity default tool keys.
    public static let eraser = PencilAction.shortcut(Shortcut("e"))
    public static let brush = PencilAction.shortcut(Shortcut("b"))
    public static let hand = PencilAction.shortcut(Shortcut("h"))

    public var shortcut: Shortcut? {
        if case .shortcut(let s) = self { return s }
        return nil
    }

    public var display: String {
        switch self {
        case .none: return "Keine"
        case .shortcut(let s): return s.display
        }
    }
}

public enum ZoomMethod: String, Codable, CaseIterable, Sendable {
    /// Scroll events with a held modifier. Many Mac drawing apps zoom with ⌘ or ⌥ + scroll;
    /// which one Affinity uses depends on its preferences, so it is selectable.
    case commandScroll, optionScroll, controlScroll
    /// Discrete ⌘+ / ⌘- shortcuts, one per zoom step.
    case keyboardSteps
    case off

    public var modifiers: ModifierSet {
        switch self {
        case .commandScroll: return .command
        case .optionScroll: return .option
        case .controlScroll: return .control
        default: return []
        }
    }

    public var title: String {
        switch self {
        case .commandScroll: return "⌘ + Scrollen"
        case .optionScroll: return "⌥ + Scrollen"
        case .controlScroll: return "⌃ + Scrollen"
        case .keyboardSteps: return "⌘+ / ⌘− Tasten"
        case .off: return "Aus"
        }
    }
}

public struct ShortcutButton: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var title: String
    public var shortcut: Shortcut
    public init(id: UUID = UUID(), title: String, shortcut: Shortcut) {
        self.id = id; self.title = title; self.shortcut = shortcut
    }
}

/// All iPad-side input settings. Stored in UserDefaults on the iPad (not secret).
public struct InputSettings: Codable, Equatable, Sendable {
    public var pressure = PressureCurve()
    public var tilt = TiltConverter()
    public var sendHover = true
    public var sendRoll = true

    public var doubleTap: PencilAction = .eraser
    public var squeeze: PencilAction = .undo
    public var twoFingerTap: PencilAction = .undo
    public var threeFingerTap: PencilAction = .redo

    public var panEnabled = true
    public var invertPan = false
    public var zoomMethod: ZoomMethod = .commandScroll
    /// Scroll units (fraction of capture height) per doubling of pinch scale.
    public var zoomSensitivity: Double = 0.25
    public var rotateLeft: PencilAction = .none
    public var rotateRight: PencilAction = .none
    public var rotateStepDegrees: Double = 15

    /// Swap the ISO keys "^" and "<" (some keyboards report them the other way round).
    public var swapISOKeys = false
    /// Trackpad/mouse on the iPad controls the Mac's pointer.
    public var trackpadAsMouse = true
    /// Hide the iPad's own pointer over the picture (the Mac cursor in the video is shown instead).
    public var hideIPadPointer = true

    public var showShortcutBar = true
    public var shortcutBar: [ShortcutButton] = [
        ShortcutButton(title: "Undo", shortcut: Shortcut("z", .command)),
        ShortcutButton(title: "Redo", shortcut: Shortcut("z", [.command, .shift])),
        ShortcutButton(title: "Pinsel", shortcut: Shortcut("b")),
        ShortcutButton(title: "Radierer", shortcut: Shortcut("e")),
        ShortcutButton(title: "Hand", shortcut: Shortcut("h")),
    ]

    public init() {}

    private enum CodingKeys: String, CodingKey {
        case pressure, tilt, sendHover, sendRoll, doubleTap, squeeze, twoFingerTap, threeFingerTap
        case panEnabled, invertPan, zoomMethod, zoomSensitivity, rotateLeft, rotateRight, rotateStepDegrees
        case swapISOKeys, trackpadAsMouse, hideIPadPointer, showShortcutBar, shortcutBar
    }

    /// Tolerates settings saved by older versions: missing keys keep their defaults.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func get<T: Decodable>(_ k: CodingKeys, _ into: inout T) throws {
            if let v = try c.decodeIfPresent(T.self, forKey: k) { into = v }
        }
        try get(.pressure, &pressure); try get(.tilt, &tilt)
        try get(.sendHover, &sendHover); try get(.sendRoll, &sendRoll)
        try get(.doubleTap, &doubleTap); try get(.squeeze, &squeeze)
        try get(.twoFingerTap, &twoFingerTap); try get(.threeFingerTap, &threeFingerTap)
        try get(.panEnabled, &panEnabled); try get(.invertPan, &invertPan)
        try get(.zoomMethod, &zoomMethod); try get(.zoomSensitivity, &zoomSensitivity)
        try get(.rotateLeft, &rotateLeft); try get(.rotateRight, &rotateRight)
        try get(.rotateStepDegrees, &rotateStepDegrees)
        try get(.swapISOKeys, &swapISOKeys)
        try get(.trackpadAsMouse, &trackpadAsMouse); try get(.hideIPadPointer, &hideIPadPointer)
        try get(.showShortcutBar, &showShortcutBar); try get(.shortcutBar, &shortcutBar)
    }
}
