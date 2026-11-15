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
    /// macOS system shortcuts (System Settings → Keyboard → Shortcuts → Mission Control, on by default).
    public static let desktopLeft = PencilAction.shortcut(Shortcut("left", .control))
    public static let desktopRight = PencilAction.shortcut(Shortcut("right", .control))
    public static let missionControl = PencilAction.shortcut(Shortcut("up", .control))
    public static let appWindows = PencilAction.shortcut(Shortcut("down", .control))

    public var shortcut: Shortcut? {
        if case .shortcut(let s) = self { return s }
        return nil
    }

    public var display: String {
        switch self {
        case .none: return L("Keine")
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
        case .commandScroll: return L("⌘ + Scrollen")
        case .optionScroll: return L("⌥ + Scrollen")
        case .controlScroll: return L("⌃ + Scrollen")
        case .keyboardSteps: return L("⌘+ / ⌘− Tasten")
        case .off: return L("Aus")
        }
    }
}

/// What a single finger does on the canvas (like the touch ring of a pen display).
public enum FingerMode: String, Codable, CaseIterable, Sendable {
    /// Fingers only do multi-finger gestures (strict palm rejection).
    case off
    /// Tap = click, drag = click-and-drag, hold = right click. Draws without pressure in drawing apps.
    case mouse
    /// Like the Pencil with a fixed pressure (tablet events), hold = right click.
    case pen

    public var title: String {
        switch self {
        case .off: return L("Aus")
        case .mouse: return L("Maus")
        case .pen: return L("Stift (fester Druck)")
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

    /// Smoothing of the Pencil path and of the pressure (0 = off … 1 = strong, adds lag).
    public var positionSmoothing: Double = 0
    public var pressureSmoothing: Double = 0.15

    public var fingerMode: FingerMode = .mouse
    /// Pressure used in `.pen` finger mode.
    public var fingerPressure: Double = 0.5
    public var longPressRightClick = true
    /// Touches with a larger contact radius (points) count as palm and are ignored.
    public var palmRadius: Double = 32
    /// Like a Mac trackpad: fingers move left → the desktop on the right slides in.
    public var threeFingerSwipeLeft: PencilAction = .desktopRight
    public var threeFingerSwipeRight: PencilAction = .desktopLeft
    public var threeFingerSwipeUp: PencilAction = .missionControl
    public var threeFingerSwipeDown: PencilAction = .appWindows
    public var fourFingerTap: PencilAction = .none

    /// Swap the ISO keys "^" and "<" (some keyboards report them the other way round).
    public var swapISOKeys = false
    /// Trackpad/mouse on the iPad controls the Mac's pointer.
    public var trackpadAsMouse = true
    /// Hide the iPad's own pointer over the picture (the Mac cursor in the video is shown instead).
    public var hideIPadPointer = true

    public var showShortcutBar = true
    /// Shortcut bar on the right edge (for left-handed use, so the drawing hand doesn't cover it).
    public var shortcutBarOnRight = false
    public var shortcutBar: [ShortcutButton] = [
        ShortcutButton(title: "Undo", shortcut: Shortcut("z", .command)),
        ShortcutButton(title: "Redo", shortcut: Shortcut("z", [.command, .shift])),
        ShortcutButton(title: L("Pinsel"), shortcut: Shortcut("b")),
        ShortcutButton(title: L("Radierer"), shortcut: Shortcut("e")),
        ShortcutButton(title: L("Hand"), shortcut: Shortcut("h")),
    ]

    public init() {}

    private enum CodingKeys: String, CodingKey {
        case pressure, tilt, sendHover, sendRoll, doubleTap, squeeze, twoFingerTap, threeFingerTap
        case panEnabled, invertPan, zoomMethod, zoomSensitivity, rotateLeft, rotateRight, rotateStepDegrees
        case positionSmoothing, pressureSmoothing
        case fingerMode, fingerPressure, longPressRightClick, palmRadius
        case threeFingerSwipeLeft, threeFingerSwipeRight, threeFingerSwipeUp, threeFingerSwipeDown, fourFingerTap
        case swapISOKeys, trackpadAsMouse, hideIPadPointer, showShortcutBar, shortcutBarOnRight, shortcutBar
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
        try get(.positionSmoothing, &positionSmoothing); try get(.pressureSmoothing, &pressureSmoothing)
        try get(.fingerMode, &fingerMode); try get(.fingerPressure, &fingerPressure)
        try get(.longPressRightClick, &longPressRightClick); try get(.palmRadius, &palmRadius)
        try get(.threeFingerSwipeLeft, &threeFingerSwipeLeft); try get(.threeFingerSwipeRight, &threeFingerSwipeRight)
        try get(.threeFingerSwipeUp, &threeFingerSwipeUp); try get(.threeFingerSwipeDown, &threeFingerSwipeDown)
        try get(.fourFingerTap, &fourFingerTap)
        try get(.swapISOKeys, &swapISOKeys)
        try get(.trackpadAsMouse, &trackpadAsMouse); try get(.hideIPadPointer, &hideIPadPointer)
        try get(.shortcutBarOnRight, &shortcutBarOnRight)
        try get(.showShortcutBar, &showShortcutBar); try get(.shortcutBar, &shortcutBar)
    }
}
