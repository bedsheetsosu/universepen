import Foundation

/// What a Pencil gesture (double tap, squeeze) or a finger tap triggers.
public enum PencilAction: Codable, Hashable, Sendable {
    case none
    case shortcut(Shortcut)
    /// Opens the radial menu at the Pencil tip (Pencil Pro squeeze / double tap).
    case radialMenu

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
        case .radialMenu: return L("Radialmenü")
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

/// Keys a bar button can hold down while the finger rests on it (USB HID usages).
public enum HoldKey: UInt16, CaseIterable, Codable, Sendable {
    case shift = 0xE1, option = 0xE2, command = 0xE3, control = 0xE0, space = 0x2C

    public var symbol: String {
        switch self {
        case .shift: return "⇧"
        case .option: return "⌥"
        case .command: return "⌘"
        case .control: return "⌃"
        case .space: return "␣"
        }
    }
}

public struct ShortcutButton: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var title: String
    public var shortcut: Shortcut
    /// If set, the button holds this key down while touched (e.g. ⇧ or Space while drawing)
    /// instead of sending `shortcut` once.
    public var hold: HoldKey?
    public init(id: UUID = UUID(), title: String, shortcut: Shortcut, hold: HoldKey? = nil) {
        self.id = id; self.title = title; self.shortcut = shortcut; self.hold = hold
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
    /// Own bars per Mac app (bundle ID); the bar switches automatically with the front app.
    public var appShortcutBars: [String: [ShortcutButton]] = [:]
    /// Display names of apps with an own bar (for the settings list).
    public var appNames: [String: String] = [:]
    public var shortcutBar: [ShortcutButton] = [
        ShortcutButton(title: "Undo", shortcut: Shortcut("z", .command)),
        ShortcutButton(title: "Redo", shortcut: Shortcut("z", [.command, .shift])),
        ShortcutButton(title: L("Pinsel"), shortcut: Shortcut("b")),
        ShortcutButton(title: L("Radierer"), shortcut: Shortcut("e")),
        ShortcutButton(title: L("Hand"), shortcut: Shortcut("h")),
        ShortcutButton(title: "⇧", shortcut: Shortcut("a"), hold: .shift),
        ShortcutButton(title: "⌥", shortcut: Shortcut("a"), hold: .option),
    ]

    /// Items of the radial menu (Pencil Pro squeeze), clockwise from the top. 2…8 items.
    public var radialMenu: [ShortcutButton] = InputSettings.defaultRadialMenu
    public static let maxRadialItems = 8
    public static var defaultRadialMenu: [ShortcutButton] {
        [
            ShortcutButton(title: "Undo", shortcut: Shortcut("z", .command)),
            ShortcutButton(title: L("Pinsel"), shortcut: Shortcut("b")),
            ShortcutButton(title: L("Radierer"), shortcut: Shortcut("e")),
            ShortcutButton(title: L("Pipette"), shortcut: Shortcut("i")),
            ShortcutButton(title: L("Hand"), shortcut: Shortcut("h")),
            ShortcutButton(title: "Redo", shortcut: Shortcut("z", [.command, .shift])),
        ]
    }

    /// Own Pencil settings per Mac app (bundle ID); they replace the standard ones while that app
    /// is in front on the Mac.
    public var appPenProfiles: [String: PenProfile] = [:]

    /// Mac apps (bundle ID → name) that get game mode: maximum picture quality and no smoothing
    /// while they are in front (e.g. osu!).
    public var gameApps: [String: String] = [:]

    /// Two fingers rest, then drag left/right = undo/redo step by step.
    public var undoScrub = true
    /// Finger travel (points) per undo/redo step.
    public var undoScrubStep: Double = 40

    public init() {}

    public func isGame(_ bundleID: String?) -> Bool { bundleID.map { gameApps[$0] != nil } ?? false }

    /// The Pencil part of these settings (what a per-app profile can override).
    public var penProfile: PenProfile {
        get { PenProfile(pressure: pressure, positionSmoothing: positionSmoothing, pressureSmoothing: pressureSmoothing,
                         doubleTap: doubleTap, squeeze: squeeze) }
        set {
            pressure = newValue.pressure
            positionSmoothing = newValue.positionSmoothing
            pressureSmoothing = newValue.pressureSmoothing
            doubleTap = newValue.doubleTap
            squeeze = newValue.squeeze
        }
    }

    /// Settings in effect while the app with `bundleID` is in front on the Mac.
    public func effective(for bundleID: String?) -> InputSettings {
        var s = self
        if let bundleID, let p = appPenProfiles[bundleID] { s.penProfile = p }
        if isGame(bundleID) {
            // Smoothing adds lag; a game wants the raw Pencil.
            s.positionSmoothing = 0
            s.pressureSmoothing = 0
        }
        return s
    }

    private enum CodingKeys: String, CodingKey {
        case pressure, tilt, sendHover, sendRoll, doubleTap, squeeze, twoFingerTap, threeFingerTap
        case panEnabled, invertPan, zoomMethod, zoomSensitivity, rotateLeft, rotateRight, rotateStepDegrees
        case positionSmoothing, pressureSmoothing
        case fingerMode, fingerPressure, longPressRightClick, palmRadius
        case threeFingerSwipeLeft, threeFingerSwipeRight, threeFingerSwipeUp, threeFingerSwipeDown, fourFingerTap
        case swapISOKeys, trackpadAsMouse, hideIPadPointer, showShortcutBar, shortcutBarOnRight, shortcutBar
        case appShortcutBars, appNames, radialMenu, appPenProfiles, gameApps, undoScrub, undoScrubStep
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
        try get(.appShortcutBars, &appShortcutBars); try get(.appNames, &appNames)
        try get(.radialMenu, &radialMenu); try get(.appPenProfiles, &appPenProfiles)
        try get(.gameApps, &gameApps); try get(.undoScrub, &undoScrub); try get(.undoScrubStep, &undoScrubStep)
    }
}

/// Pencil settings that can differ per Mac app.
public struct PenProfile: Codable, Equatable, Sendable {
    public var pressure: PressureCurve
    public var positionSmoothing: Double
    public var pressureSmoothing: Double
    public var doubleTap: PencilAction
    public var squeeze: PencilAction

    public init(pressure: PressureCurve, positionSmoothing: Double, pressureSmoothing: Double,
                doubleTap: PencilAction, squeeze: PencilAction) {
        self.pressure = pressure
        self.positionSmoothing = positionSmoothing
        self.pressureSmoothing = pressureSmoothing
        self.doubleTap = doubleTap
        self.squeeze = squeeze
    }
}

/// Geometry of the radial menu: which item lies under a point.
public enum RadialMenuLayout {
    public static let radius: Double = 112
    /// Inside this distance from the centre nothing is selected (lets you back out).
    public static let deadZone: Double = 38
    public static let outerLimit: Double = 190

    /// Centre of item `i` of `count`, relative to the menu centre (item 0 at the top, clockwise).
    public static func offset(of i: Int, count: Int) -> (x: Double, y: Double) {
        let a = -Double.pi / 2 + Double(i) * 2 * .pi / Double(max(count, 1))
        return (radius * cos(a), radius * sin(a))
    }

    /// Item under the point (dx, dy) from the centre, or nil in the dead zone / far outside.
    public static func item(dx: Double, dy: Double, count: Int) -> Int? {
        guard count > 0 else { return nil }
        let d = (dx * dx + dy * dy).squareRoot()
        guard d >= deadZone, d <= outerLimit else { return nil }
        var a = atan2(dy, dx) + .pi / 2          // 0 at the top, clockwise
        if a < 0 { a += 2 * .pi }
        let sector = 2 * .pi / Double(count)
        return Int(((a + sector / 2) / sector).rounded(.down)) % count
    }
}
