import SwiftUI
import TafelKit

/// Ring of actions around the Pencil tip, opened by squeeze (or double tap) when set to
/// "Radialmenü". Hover over an item and squeeze again, or tap it. Tap the centre or outside to
/// close. The highlight change and the pick give a haptic tick on the Pencil Pro.
struct RadialMenuView: View {
    @EnvironmentObject var model: ClientModel
    let center: CGPoint

    private var items: [ShortcutButton] { model.effectiveSettings.radialMenu }

    var body: some View {
        GeometryReader { g in
            let origin = g.frame(in: .global).origin
            let c = CGPoint(x: center.x - origin.x, y: center.y - origin.y)
            ZStack {
                // Catches taps outside the ring (close) and keeps the Pencil off the Mac meanwhile.
                Color.black.opacity(0.001)
                    .contentShape(Rectangle())
                    .onTapGesture { model.closeRadial() }

                Circle()
                    .fill(.black.opacity(0.25))
                    .frame(width: RadialMenuLayout.radius * 2 + 90, height: RadialMenuLayout.radius * 2 + 90)
                    .tafelGlass(Circle())
                    .position(c)
                    .allowsHitTesting(false)

                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 44, height: 44)
                    .background(.white.opacity(0.08), in: Circle())
                    .position(c)
                    .onTapGesture { model.closeRadial() }

                ForEach(Array(items.enumerated()), id: \.element.id) { i, item in
                    let o = RadialMenuLayout.offset(of: i, count: items.count)
                    let on = model.radialHighlight == i
                    Text(item.title)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(2)
                        .minimumScaleFactor(0.6)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(on ? Brand.slateDeep : .primary)
                        .frame(width: 66, height: 66)
                        .background(on ? AnyShapeStyle(Brand.mint) : AnyShapeStyle(Color.white.opacity(0.1)), in: Circle())
                        .overlay(Circle().strokeBorder(.white.opacity(on ? 0 : 0.12)))
                        .scaleEffect(on ? 1.12 : 1)
                        .position(x: c.x + o.x, y: c.y + o.y)
                        .onTapGesture { model.pickRadial(i) }
                }
            }
            .onContinuousHover(coordinateSpace: .local) { phase in
                switch phase {
                case .active(let p):
                    let i = RadialMenuLayout.item(dx: p.x - c.x, dy: p.y - c.y, count: items.count)
                    if i != model.radialHighlight { model.radialHighlight = i }
                case .ended:
                    model.radialHighlight = nil
                }
            }
        }
        .ignoresSafeArea()
        .animation(Brand.spring, value: model.radialHighlight)
        .sensoryFeedback(.alignment, trigger: model.radialHighlight) { _, new in new != nil }
        .transition(.scale(scale: 0.6).combined(with: .opacity))
    }
}
