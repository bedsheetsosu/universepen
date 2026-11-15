import Foundation
import CoreGraphics

public enum Geometry {
    /// Rectangle of `content` scaled to fit inside `container`, centered (aspect fit).
    public static func aspectFit(content: CGSize, in container: CGRect) -> CGRect {
        guard content.width > 0, content.height > 0, container.width > 0, container.height > 0 else { return container }
        let scale = min(container.width / content.width, container.height / content.height)
        let size = CGSize(width: content.width * scale, height: content.height * scale)
        return CGRect(x: container.midX - size.width / 2, y: container.midY - size.height / 2,
                      width: size.width, height: size.height)
    }

    /// Largest rect with the given aspect ratio (w/h) inside `bounds`, scaled by `zoom` (0...1],
    /// positioned by `anchor` (0...1 per axis, 0.5 = centered).
    public static func region(aspect: Double, in bounds: CGRect, zoom: Double = 1, anchor: CGPoint = CGPoint(x: 0.5, y: 0.5)) -> CGRect {
        guard aspect > 0, bounds.width > 0, bounds.height > 0 else { return bounds }
        let z = min(max(zoom, 0.1), 1)
        var w = bounds.width
        var h = w / aspect
        if h > bounds.height {
            h = bounds.height
            w = h * aspect
        }
        w *= z; h *= z
        let ax = min(max(anchor.x, 0), 1), ay = min(max(anchor.y, 0), 1)
        return CGRect(x: bounds.minX + (bounds.width - w) * ax,
                      y: bounds.minY + (bounds.height - h) * ay,
                      width: w, height: h)
    }

    /// Normalized (0...1) position of `point` inside `rect`, clamped. Origin top-left.
    public static func normalized(_ point: CGPoint, in rect: CGRect) -> CGPoint {
        guard rect.width > 0, rect.height > 0 else { return .zero }
        return CGPoint(x: min(max((point.x - rect.minX) / rect.width, 0), 1),
                       y: min(max((point.y - rect.minY) / rect.height, 0), 1))
    }

    /// Maps a normalized point back to a point in `region` (e.g. global Mac display coordinates).
    public static func denormalized(_ p: CGPoint, in region: CGRect) -> CGPoint {
        CGPoint(x: region.minX + p.x * region.width, y: region.minY + p.y * region.height)
    }

    /// Output stream size: source aspect fitted into the target pixel size times `scale`,
    /// rounded down to even numbers (required by 4:2:0 encoders).
    public static func streamSize(sourceAspect: Double, targetWidth: Int, targetHeight: Int, scale: Double) -> (width: Int, height: Int) {
        let s = min(max(scale, 0.25), 1)
        let tw = Double(targetWidth) * s, th = Double(targetHeight) * s
        guard sourceAspect > 0, tw > 0, th > 0 else { return (2, 2) }
        var w = tw, h = tw / sourceAspect
        if h > th { h = th; w = th * sourceAspect }
        func even(_ v: Double) -> Int { max(2, Int(v) & ~1) }
        return (even(w), even(h))
    }
}

/// Converts Äbbl Pencil angles to Wacom-style tilt values (-1...1 per axis).
///
/// altitude: 0 = flat on the glass, π/2 = perpendicular. azimuth: direction in the view's
/// coordinate space, 0 = +x (right), positive towards +y (down). The *sign convention* that
/// drawing apps on macOS expect has not been verified against real hardware yet, so both axes
/// can be inverted in the settings.
public struct TiltConverter: Codable, Equatable, Sendable {
    public var invertX: Bool
    public var invertY: Bool

    public init(invertX: Bool = false, invertY: Bool = false) {
        self.invertX = invertX
        self.invertY = invertY
    }

    public func tilt(altitude: Double, azimuth: Double) -> (x: Double, y: Double) {
        let magnitude = cos(min(max(altitude, 0), .pi / 2))
        var x = magnitude * cos(azimuth)
        var y = magnitude * sin(azimuth)
        if invertX { x = -x }
        if invertY { y = -y }
        return (min(max(x, -1), 1), min(max(y, -1), 1))
    }
}

/// Simple gamma pressure curve with a minimum output while touching, so very light strokes
/// still register in apps that treat pressure 0 as "no stroke".
public struct PressureCurve: Codable, Equatable, Sendable {
    /// < 1 = softer (more output for light pressure), > 1 = harder.
    public var gamma: Double
    public var minimum: Double

    public init(gamma: Double = 1.0, minimum: Double = 0.01) {
        self.gamma = gamma
        self.minimum = minimum
    }

    public func apply(force: Double, maximumForce: Double) -> Double {
        guard maximumForce > 0 else { return 1 }
        let n = min(max(force / maximumForce, 0), 1)
        let g = min(max(gamma, 0.2), 5)
        return max(pow(n, g), minimum)
    }
}

/// Integer remainder accumulator for scroll deltas.
public struct DeltaAccumulator: Sendable {
    private var rest: Double = 0
    public init() {}
    public mutating func take(_ delta: Double) -> Int {
        rest += delta
        let whole = rest.rounded(.towardZero)
        rest -= whole
        return Int(whole)
    }
}

/// Converts a continuous value (pinch log-scale, rotation angle) into discrete steps.
public struct StepAccumulator: Sendable {
    public var stepSize: Double
    private var acc: Double = 0
    public init(stepSize: Double) { self.stepSize = stepSize }
    public mutating func reset() { acc = 0 }
    /// Returns signed number of whole steps crossed by adding `delta`.
    public mutating func add(_ delta: Double) -> Int {
        guard stepSize > 0 else { return 0 }
        acc += delta
        let steps = Int((acc / stepSize).rounded(.towardZero))
        acc -= Double(steps) * stepSize
        return steps
    }
}
