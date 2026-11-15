import SwiftUI

/// Shared look of both apps (colours from the app icon).
public enum Brand {
    public static let slateTop = Color(red: 0x2B / 255, green: 0x4A / 255, blue: 0x55 / 255)
    public static let slate = Color(red: 0x16 / 255, green: 0x26 / 255, blue: 0x2E / 255)
    public static let slateDeep = Color(red: 0x0C / 255, green: 0x16 / 255, blue: 0x1B / 255)
    public static let mint = Color(red: 0x7F / 255, green: 0xE3 / 255, blue: 0xD3 / 255)
    public static let mintBright = Color(red: 0xBF / 255, green: 0xF5 / 255, blue: 0xEC / 255)

    public static var background: LinearGradient {
        LinearGradient(colors: [slateTop, slate, slateDeep], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    public static let spring = Animation.spring(response: 0.45, dampingFraction: 0.82)
}

public extension View {
    /// Liquid Glass where available, a material otherwise.
    @ViewBuilder func tafelGlass<S: Shape>(_ shape: S, tint: Color? = nil) -> some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            self.glassEffect(tint.map { .regular.tint($0) } ?? .regular, in: shape)
        } else {
            self.background(.ultraThinMaterial, in: shape)
        }
    }

    /// Rounded card used on both platforms.
    func tafelCard(padding: CGFloat = 16) -> some View {
        self
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(.white.opacity(0.08)))
    }
}

/// Expanding rings, e.g. "searching" or "waiting for the iPad".
public struct PulseRings: View {
    var color: Color
    var active: Bool
    @State private var phase = false

    public init(color: Color = Brand.mint, active: Bool = true) {
        self.color = color
        self.active = active
    }

    public var body: some View {
        ZStack {
            ForEach(0..<3) { i in
                Circle()
                    .stroke(color.opacity(0.6), lineWidth: 1.5)
                    .scaleEffect(phase ? 1.9 : 0.6)
                    .opacity(phase ? 0 : 0.9)
                    .animation(active ? .easeOut(duration: 2.4).repeatForever(autoreverses: false).delay(Double(i) * 0.8) : .default,
                               value: phase)
            }
        }
        .opacity(active ? 1 : 0)
        .onAppear { phase = true }
    }
}

/// Small app mark (slate tile with a stroke), drawn in SwiftUI so it scales crisply.
public struct TafelMark: View {
    public init() {}
    public var body: some View {
        GeometryReader { g in
            let s = min(g.size.width, g.size.height)
            ZStack {
                RoundedRectangle(cornerRadius: s * 0.24, style: .continuous)
                    .fill(Brand.background)
                RoundedRectangle(cornerRadius: s * 0.24, style: .continuous)
                    .strokeBorder(.white.opacity(0.12))
                Path { p in
                    p.move(to: CGPoint(x: s * 0.16, y: s * 0.60))
                    p.addCurve(to: CGPoint(x: s * 0.62, y: s * 0.60),
                               control1: CGPoint(x: s * 0.32, y: s * 0.20), control2: CGPoint(x: s * 0.44, y: s * 0.95))
                }
                .stroke(LinearGradient(colors: [.white, Brand.mint], startPoint: .leading, endPoint: .trailing),
                        style: StrokeStyle(lineWidth: s * 0.065, lineCap: .round))
                .shadow(color: Brand.mint.opacity(0.7), radius: s * 0.05)
                Capsule()
                    .fill(.white)
                    .frame(width: s * 0.36, height: s * 0.075)
                    .rotationEffect(.degrees(-45))
                    .offset(x: s * 0.13, y: -s * 0.02)
                    .shadow(color: .black.opacity(0.4), radius: s * 0.02, y: s * 0.01)
            }
            .frame(width: s, height: s)
        }
        .aspectRatio(1, contentMode: .fit)
    }
}
