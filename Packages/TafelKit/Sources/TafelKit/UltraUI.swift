import SwiftUI

/// UltraUI – the design system both apps are built from: shapes, motion, surfaces and controls.
///
/// Two kinds of surface, on purpose:
/// - `ultraPanel` floats over the live Mac picture. It is a calm frosted material; Liquid Glass
///   adapts its brightness to what is behind it, which over moving video reads as pulsing.
/// - `ultraGlass` is real Liquid Glass (iOS/macOS 26+) for everything on a still background.
public enum Ultra {
    public static let tileRadius: CGFloat = 16
    public static let cardRadius: CGFloat = 22
    public static let panelRadius: CGFloat = 28

    /// Answer to a touch: selections, toggles.
    public static var snappy: Animation {
        Brand.reduceMotion ? .easeInOut(duration: 0.15) : .spring(response: 0.3, dampingFraction: 0.82)
    }

    /// Panels and pages arriving or leaving.
    public static var smooth: Animation {
        Brand.reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.42, dampingFraction: 0.86)
    }

    /// Emphasis: hero marks, success.
    public static var bouncy: Animation {
        Brand.reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.5, dampingFraction: 0.62)
    }

    public static func shape(_ radius: CGFloat = tileRadius) -> RoundedRectangle {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
    }

    /// Light that seems to come from the top-left: the hairline every raised surface gets.
    public static var edgeLight: LinearGradient {
        LinearGradient(colors: [.white.opacity(0.30), .white.opacity(0.05), .white.opacity(0.14)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// Fill of anything that is "on".
    public static var accentFill: LinearGradient {
        LinearGradient(colors: [Brand.mintBright, Brand.mint], startPoint: .top, endPoint: .bottom)
    }
}

// MARK: - Surfaces

public extension View {
    /// Floating panel over the live picture (see `Ultra`).
    func ultraPanel<S: InsettableShape>(_ shape: S, shadow: Bool = true) -> some View {
        self
            .background(.ultraThinMaterial, in: shape)
            .background(Color.black.opacity(0.42), in: shape)
            .overlay(shape.strokeBorder(Ultra.edgeLight, lineWidth: 1))
            .clipShape(shape)
            .shadow(color: .black.opacity(shadow ? 0.45 : 0), radius: 24, y: 12)
            .environment(\.colorScheme, .dark)
    }

    /// Liquid Glass on a still background; a material with the same edge light before iOS/macOS 26.
    @ViewBuilder func ultraGlass<S: InsettableShape>(_ shape: S, tint: Color? = nil, interactive: Bool = false) -> some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            let glass: Glass = tint.map { Glass.regular.tint($0) } ?? .regular
            self.glassEffect(interactive ? glass.interactive() : glass, in: shape)
        } else {
            self
                .background(.ultraThinMaterial, in: shape)
                .background((tint ?? .clear).opacity(0.25), in: shape)
                .overlay(shape.strokeBorder(Ultra.edgeLight, lineWidth: 1))
        }
    }

    /// Card on the app's own background (connect screen, settings, the Mac window).
    func ultraCard(padding: CGFloat = 18, radius: CGFloat = Ultra.cardRadius) -> some View {
        self
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.white.opacity(0.06), in: Ultra.shape(radius))
            .overlay(Ultra.shape(radius).strokeBorder(Ultra.edgeLight.opacity(0.6), lineWidth: 1))
    }
}

// MARK: - Controls

/// Press feedback shared by every UltraUI control: it gives a little and lights up.
public struct UltraPress: ButtonStyle {
    var scale: CGFloat
    public init(scale: CGFloat = 0.94) { self.scale = scale }
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .brightness(configuration.isPressed ? 0.12 : 0)
            .animation(Ultra.snappy, value: configuration.isPressed)
    }
}

/// Square-ish button with a symbol and a short name; lit in the accent colour while `on`.
public struct UltraTile: View {
    @ObservedObject private var theme = Theme.shared
    let symbol: String
    let title: String
    var on: Bool
    var enabled: Bool
    var minHeight: CGFloat
    let action: () -> Void

    public init(_ title: String, symbol: String, on: Bool = false, enabled: Bool = true, minHeight: CGFloat = 64,
                action: @escaping () -> Void) {
        self.title = title; self.symbol = symbol; self.on = on; self.enabled = enabled
        self.minHeight = minHeight; self.action = action
    }

    public var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 19, weight: .semibold))
                    .symbolEffect(.bounce, value: on)
                    .frame(height: 22)
                Text(title)
                    .font(.caption2.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
            }
            .padding(.horizontal, 4)
            .frame(maxWidth: .infinity, minHeight: minHeight)
            .foregroundStyle(on ? Brand.slateDeep : Color.white.opacity(0.92))
            .background {
                if on { Ultra.shape().fill(Ultra.accentFill) } else { Ultra.shape().fill(.white.opacity(0.075)) }
            }
            .overlay(Ultra.shape().strokeBorder(.white.opacity(on ? 0.35 : 0.07), lineWidth: 1))
            .shadow(color: on ? Brand.mint.opacity(0.4) : .clear, radius: 9, y: 2)
            .contentShape(Ultra.shape())
        }
        .buttonStyle(UltraPress())
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.38)
        .animation(Ultra.snappy, value: on)
        .accessibilityLabel(title)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// List row inside a panel: symbol, title, optional detail, and a mark when chosen.
public struct UltraRow: View {
    @ObservedObject private var theme = Theme.shared
    let title: String
    var symbol: String?
    var detail: String?
    var checked: Bool
    var destructive: Bool
    var trailing: String?
    var enabled: Bool
    let action: () -> Void

    public init(_ title: String, symbol: String? = nil, detail: String? = nil, checked: Bool = false, destructive: Bool = false,
                trailing: String? = nil, enabled: Bool = true, action: @escaping () -> Void) {
        self.title = title; self.symbol = symbol; self.detail = detail; self.checked = checked
        self.destructive = destructive; self.trailing = trailing; self.enabled = enabled; self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                if let symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(destructive ? Color.red : checked ? Brand.slateDeep : Color.white.opacity(0.85))
                        .frame(width: 30, height: 30)
                        .background {
                            if checked && !destructive { Circle().fill(Ultra.accentFill) }
                            else { Circle().fill(destructive ? Color.red.opacity(0.16) : Color.white.opacity(0.09)) }
                        }
                        .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.callout.weight(.medium))
                        .foregroundStyle(destructive ? Color.red : Color.white.opacity(0.95))
                        .lineLimit(2).multilineTextAlignment(.leading)
                    if let detail {
                        Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Spacer(minLength: 4)
                if checked {
                    Image(systemName: "checkmark").font(.footnote.weight(.bold)).foregroundStyle(Brand.mint)
                        .transition(.scale.combined(with: .opacity))
                }
                if let trailing {
                    Image(systemName: trailing).font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 7).padding(.horizontal, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(UltraRowPress())
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.38)
        .animation(Ultra.snappy, value: checked)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(checked ? .isSelected : [])
    }
}

struct UltraRowPress: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(.white.opacity(configuration.isPressed ? 0.11 : 0), in: Ultra.shape(12))
            .animation(Ultra.snappy, value: configuration.isPressed)
    }
}

/// Small caps heading of a group.
public struct UltraHeader: View {
    let title: String
    public init(_ title: String) { self.title = title }
    public var body: some View {
        Text(title.uppercased())
            .font(.caption2.weight(.bold))
            .tracking(0.8)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
            .accessibilityAddTraits(.isHeader)
    }
}

/// Choice between a few options with a highlight that slides to the chosen one.
public struct UltraSegmented<Value: Hashable>: View {
    @ObservedObject private var theme = Theme.shared
    let options: [(value: Value, title: String, symbol: String?)]
    @Binding var selection: Value
    /// Show the title only on the chosen option (compact tab bars).
    var collapsesTitles: Bool
    @Namespace private var space

    public init(_ options: [(value: Value, title: String, symbol: String?)], selection: Binding<Value>, collapsesTitles: Bool = false) {
        self.options = options
        self._selection = selection
        self.collapsesTitles = collapsesTitles
    }

    public var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.value) { o in
                let on = o.value == selection
                Button {
                    withAnimation(Ultra.snappy) { selection = o.value }
                } label: {
                    HStack(spacing: 6) {
                        if let s = o.symbol {
                            Image(systemName: s).font(.system(size: 14, weight: .semibold))
                        }
                        if !collapsesTitles || on || o.symbol == nil {
                            Text(o.title).font(.footnote.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.7)
                                .transition(.opacity.combined(with: .scale(scale: 0.8)))
                        }
                    }
                    .padding(.horizontal, 10)
                    .frame(maxWidth: collapsesTitles && !on ? 44 : .infinity, minHeight: 34)
                    .foregroundStyle(on ? Brand.slateDeep : Color.white.opacity(0.8))
                    .background {
                        if on { Capsule().fill(Ultra.accentFill).matchedGeometryEffect(id: "selection", in: space) }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(UltraPress(scale: 0.96))
                .accessibilityLabel(o.title)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(3)
        .background(.black.opacity(0.28), in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.07), lineWidth: 1))
    }
}

/// Round floating button (the dock handle, undo/redo, close).
public struct UltraRoundButton: View {
    let symbol: String
    let label: String
    var size: CGFloat
    let action: () -> Void

    public init(_ symbol: String, label: String, size: CGFloat = 40, action: @escaping () -> Void) {
        self.symbol = symbol; self.label = label; self.size = size; self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size * 0.4, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
                .contentTransition(.symbolEffect(.replace))
                .frame(width: size, height: size)
                .ultraPanel(Circle(), shadow: false)
                .contentShape(Circle())
        }
        .buttonStyle(UltraPress(scale: 0.9))
        .accessibilityLabel(label)
    }
}
