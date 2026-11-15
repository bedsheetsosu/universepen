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
/// Driven by a timeline (not an implicit repeatForever animation), so it never picks up the
/// position of a sheet or page that is animating in.
public struct PulseRings: View {
    var color: Color
    var active: Bool

    public init(color: Color = Brand.mint, active: Bool = true) {
        self.color = color
        self.active = active
    }

    public var body: some View {
        TimelineView(.animation(paused: !active)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            ZStack {
                ForEach(0..<3) { i in
                    let p = (t / 2.4 + Double(i) / 3).truncatingRemainder(dividingBy: 1)
                    Circle()
                        .stroke(color.opacity(0.6), lineWidth: 1.5)
                        .scaleEffect(0.6 + 1.3 * p)
                        .opacity(0.9 * (1 - p))
                }
            }
        }
        .opacity(active ? 1 : 0)
        .animation(.easeInOut(duration: 0.4), value: active)
        .allowsHitTesting(false)
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

/// Language tiles (flag + name in its own language). Switching is instant.
public struct LanguageChoice: View {
    @ObservedObject private var l10n = L10n.shared
    public init() {}

    public var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 10)], spacing: 10) {
            ForEach(AppLanguage.allCases) { lang in
                let on = l10n.language == lang
                Button {
                    withAnimation(Brand.spring) { l10n.language = lang }
                } label: {
                    VStack(spacing: 8) {
                        Text(lang.flag).font(.system(size: 32))
                        Text(lang.nativeName).font(.headline).lineLimit(1).minimumScaleFactor(0.7)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .foregroundStyle(on ? Brand.slateDeep : .primary)
                    .background(on ? AnyShapeStyle(Brand.mint) : AnyShapeStyle(Color.white.opacity(0.06)),
                                in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(.white.opacity(on ? 0 : 0.08)))
                    .scaleEffect(on ? 1.03 : 1)
                }
                .buttonStyle(.plain)
            }
        }
    }
}
