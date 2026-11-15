// Renders the Tafel app icons (iPad + Mac) with CoreGraphics.
// Usage:  swift Tools/make-icon.swift <output-dir>
// Writes ipad-1024.png (full-bleed square, iPadOS applies the mask) and mac-<size>.png
// (rounded "squircle" with margin and shadow, macOS icon grid).
import AppKit
import CoreGraphics

let out = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")

func color(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

/// Point on a cubic Bézier.
func bezier(_ p0: CGPoint, _ p1: CGPoint, _ p2: CGPoint, _ p3: CGPoint, _ t: CGFloat) -> CGPoint {
    let u = 1 - t
    let a = u * u * u, b = 3 * u * u * t, c = 3 * u * t * t, d = t * t * t
    return CGPoint(x: a * p0.x + b * p1.x + c * p2.x + d * p3.x, y: a * p0.y + b * p1.y + c * p2.y + d * p3.y)
}

/// Draws the artwork into a square of side `s` (origin bottom-left).
func drawArt(_ ctx: CGContext, _ s: CGFloat) {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    // Slate: deep blue-green, lighter towards the top left.
    let bg = CGGradient(colorsSpace: space, colors: [color(0x2B4A55), color(0x16262E), color(0x0C161B)] as CFArray,
                        locations: [0, 0.55, 1])!
    ctx.drawLinearGradient(bg, start: CGPoint(x: 0, y: s), end: CGPoint(x: s, y: 0), options: [])
    // Soft light spot.
    let glow = CGGradient(colorsSpace: space, colors: [color(0x6FD3C6, 0.22), color(0x6FD3C6, 0)] as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(glow, startCenter: CGPoint(x: s * 0.42, y: s * 0.55), startRadius: 0,
                           endCenter: CGPoint(x: s * 0.42, y: s * 0.55), endRadius: s * 0.55, options: [])

    // The stroke: a swoosh whose width follows a pressure curve (thin – full – thin).
    let p0 = CGPoint(x: s * 0.14, y: s * 0.40)
    let p1 = CGPoint(x: s * 0.30, y: s * 0.74)
    let p2 = CGPoint(x: s * 0.42, y: s * 0.12)
    let p3 = CGPoint(x: s * 0.60, y: s * 0.40)
    let steps = 400
    var left: [CGPoint] = [], right: [CGPoint] = []
    for i in 0...steps {
        let t = CGFloat(i) / CGFloat(steps)
        let p = bezier(p0, p1, p2, p3, t)
        let q = bezier(p0, p1, p2, p3, min(1, t + 0.001))
        let r = bezier(p0, p1, p2, p3, max(0, t - 0.001))
        var dx = q.x - r.x, dy = q.y - r.y
        let len = max(hypot(dx, dy), 0.0001); dx /= len; dy /= len
        // Pressure: quick attack, long body, tapering release.
        let pressure = pow(sin(.pi * pow(t, 0.8)), 0.7)
        let w = s * (0.004 + 0.034 * pressure)
        left.append(CGPoint(x: p.x - dy * w, y: p.y + dx * w))
        right.append(CGPoint(x: p.x + dy * w, y: p.y - dx * w))
    }
    // One closed outline: down the left edge, back along the right edge.
    // (addLines(between:) would start a new subpath each time and draw a chord.)
    let path = CGMutablePath()
    path.move(to: left[0])
    for p in left.dropFirst() { path.addLine(to: p) }
    for p in right.reversed() { path.addLine(to: p) }
    path.closeSubpath()

    // Glow under the stroke.
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: s * 0.05, color: color(0x7FF0DF, 0.55))
    ctx.addPath(path)
    ctx.setFillColor(color(0xEAFBF8))
    ctx.fillPath()
    ctx.restoreGState()
    // Stroke body: white to mint.
    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip()
    let ink = CGGradient(colorsSpace: space, colors: [color(0xFFFFFF), color(0xBFF5EC), color(0x7FE3D3)] as CFArray,
                         locations: [0, 0.6, 1])!
    ctx.drawLinearGradient(ink, start: p0, end: p3, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    ctx.restoreGState()

    // Pencil: tip resting at the end of the stroke, body rising to the upper right.
    let end = bezier(p0, p1, p2, p3, 1)
    ctx.saveGState()
    ctx.translateBy(x: end.x, y: end.y)
    ctx.rotate(by: .pi / 4)
    let bodyW = s * 0.078, coneL = s * 0.10, bodyL = s * 0.36
    // Cone (sharpened wood → graphite).
    let cone = CGMutablePath()
    cone.move(to: .zero)
    cone.addLine(to: CGPoint(x: coneL, y: bodyW / 2))
    cone.addLine(to: CGPoint(x: coneL, y: -bodyW / 2))
    cone.closeSubpath()
    ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.008), blur: s * 0.02, color: color(0x000000, 0.45))
    ctx.addPath(cone)
    ctx.setFillColor(color(0xE9EEF0))
    ctx.fillPath()
    ctx.setShadow(offset: .zero, blur: 0, color: nil)
    let tip = CGMutablePath()
    tip.move(to: .zero)
    tip.addLine(to: CGPoint(x: coneL * 0.3, y: bodyW * 0.15))
    tip.addLine(to: CGPoint(x: coneL * 0.3, y: -bodyW * 0.15))
    tip.closeSubpath()
    ctx.addPath(tip)
    ctx.setFillColor(color(0x26343A))
    ctx.fillPath()
    // Body: white barrel with soft cylinder shading.
    let body = CGPath(roundedRect: CGRect(x: coneL, y: -bodyW / 2, width: bodyL, height: bodyW),
                      cornerWidth: bodyW * 0.18, cornerHeight: bodyW * 0.18, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.01), blur: s * 0.03, color: color(0x000000, 0.5))
    ctx.addPath(body)
    ctx.setFillColor(color(0xF4F7F8))
    ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addPath(body)
    ctx.clip()
    let shade = CGGradient(colorsSpace: space, colors: [color(0xFFFFFF), color(0xF1F4F5), color(0xC9D2D6)] as CFArray,
                           locations: [0, 0.45, 1])!
    ctx.drawLinearGradient(shade, start: CGPoint(x: 0, y: bodyW / 2), end: CGPoint(x: 0, y: -bodyW / 2), options: [])
    // Flat side band (Pencil Pro detail).
    ctx.setFillColor(color(0xDDE4E7))
    ctx.fill(CGRect(x: coneL, y: -bodyW * 0.12, width: bodyL, height: bodyW * 0.08))
    ctx.restoreGState()
    ctx.restoreGState()
}

func render(_ size: Int, mac: Bool) -> Data {
    let s = CGFloat(size)
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .high
    if mac {
        // macOS grid: 824/1024 body, centred, continuous-corner radius ~ 22.5 %, drop shadow.
        let inset = s * 100 / 1024
        let rect = CGRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
        let shape = CGPath(roundedRect: rect, cornerWidth: rect.width * 0.225, cornerHeight: rect.width * 0.225, transform: nil)
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.012), blur: s * 0.03, color: color(0x000000, 0.35))
        ctx.addPath(shape)
        ctx.setFillColor(color(0x0C161B))
        ctx.fillPath()
        ctx.restoreGState()
        ctx.saveGState()
        ctx.addPath(shape)
        ctx.clip()
        ctx.translateBy(x: rect.minX, y: rect.minY)
        drawArt(ctx, rect.width)
        ctx.restoreGState()
        // Fine rim light.
        ctx.addPath(shape)
        ctx.setStrokeColor(color(0xFFFFFF, 0.10))
        ctx.setLineWidth(max(1, s / 512))
        ctx.strokePath()
    } else {
        drawArt(ctx, s)
    }
    let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
    return rep.representation(using: .png, properties: [:])!
}

try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
try render(1024, mac: false).write(to: out.appendingPathComponent("ipad-1024.png"))
for size in [16, 32, 64, 128, 256, 512, 1024] {
    try render(size, mac: true).write(to: out.appendingPathComponent("mac-\(size).png"))
}
print("Icons written to \(out.path)")
