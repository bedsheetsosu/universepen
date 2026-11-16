import UIKit
import TafelKit

/// Draws the virtual ruler (the canvas handles its touches). Translucent so the picture shows
/// through, with ticks on both edges and the angle in the middle.
final class RulerView: UIView {
    var ruler = Ruler(center: .zero) { didSet { if ruler != oldValue { setNeedsDisplay() } } }
    var accent: UIColor = .systemTeal { didSet { setNeedsDisplay() } }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        backgroundColor = .clear
        contentMode = .redraw
        isUserInteractionEnabled = false
    }
    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        let h = Ruler.thickness, l = ruler.length
        ctx.saveGState()
        ctx.translateBy(x: ruler.center.x, y: ruler.center.y)
        ctx.rotate(by: ruler.angle)
        let body = UIBezierPath(roundedRect: CGRect(x: -l / 2, y: -h / 2, width: l, height: h), cornerRadius: 14)
        UIColor.black.withAlphaComponent(0.38).setFill()
        body.fill()
        UIColor.white.withAlphaComponent(0.1).setFill()
        body.fill()
        UIColor.white.withAlphaComponent(0.45).setStroke()
        body.lineWidth = 1
        body.stroke()

        // Ticks every 10 pt, longer every 50 and 100, on both edges.
        let ticks = UIBezierPath()
        let n = Int(l / 2 / 10)
        for i in -n...n {
            let x = CGFloat(i) * 10
            let len: CGFloat = i % 10 == 0 ? 18 : i % 5 == 0 ? 12 : 6
            ticks.move(to: CGPoint(x: x, y: -h / 2)); ticks.addLine(to: CGPoint(x: x, y: -h / 2 + len))
            ticks.move(to: CGPoint(x: x, y: h / 2)); ticks.addLine(to: CGPoint(x: x, y: h / 2 - len))
        }
        UIColor.white.withAlphaComponent(0.7).setStroke()
        ticks.lineWidth = 1
        ticks.stroke()

        // Angle label.
        let label = "\(ruler.degrees)°" as NSString
        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.monospacedDigitSystemFont(ofSize: 17, weight: .semibold),
            .foregroundColor: accent,
        ]
        let size = label.size(withAttributes: attrs)
        let pill = UIBezierPath(roundedRect: CGRect(x: -size.width / 2 - 10, y: -size.height / 2 - 4,
                                                    width: size.width + 20, height: size.height + 8), cornerRadius: (size.height + 8) / 2)
        UIColor.black.withAlphaComponent(0.45).setFill()
        pill.fill()
        label.draw(at: CGPoint(x: -size.width / 2, y: -size.height / 2), withAttributes: attrs)
        ctx.restoreGState()
    }
}
