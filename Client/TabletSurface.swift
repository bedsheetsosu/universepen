import SwiftUI
import TafelKit

/// Tablet mode background: black like a screenless pen tablet, a fine dot grid and corner marks
/// for the active area (everything outside it is clamped to the area's edge).
struct TabletSurfaceView: View {
    @EnvironmentObject var model: ClientModel
    @ObservedObject var theme = Theme.shared

    var body: some View {
        GeometryReader { g in
            let r = model.settings.tabletArea.rect(in: g.size)
            ZStack {
                Color.black
                Canvas { ctx, size in
                    let step: CGFloat = 22
                    var y = step / 2
                    while y < size.height {
                        var x = step / 2
                        while x < size.width {
                            let inside = r.contains(CGPoint(x: x, y: y))
                            ctx.fill(Path(ellipseIn: CGRect(x: x - 1, y: y - 1, width: 2, height: 2)),
                                     with: .color(.white.opacity(inside ? 0.22 : 0.09)))
                            x += step
                        }
                        y += step
                    }
                }
                AreaCorners(rect: r)
                    .stroke(Brand.mint.opacity(0.85), style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
            }
            .onAppear { lockAspect(g.size) }
            .onChange(of: model.tabletAspect) { lockAspect(g.size) }
            .onChange(of: g.size) { lockAspect(g.size) }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    /// Keeps the area in the Mac display's shape (when that option is on).
    private func lockAspect(_ size: CGSize) {
        guard model.settings.tabletLockAspect else { return }
        let locked = model.settings.tabletArea.locked(to: model.tabletAspect, in: size)
        let a = model.settings.tabletArea
        if abs(locked.width - a.width) > 0.002 || abs(locked.height - a.height) > 0.002 { model.settings.tabletArea = locked }
    }
}

/// L-shaped corner marks of the active area (like the marks printed on pen tablets).
struct AreaCorners: Shape {
    var rect: CGRect
    func path(in _: CGRect) -> Path {
        let l = min(26, rect.width / 4, rect.height / 4)
        var p = Path()
        for (c, dx, dy) in [(CGPoint(x: rect.minX, y: rect.minY), 1.0, 1.0), (CGPoint(x: rect.maxX, y: rect.minY), -1.0, 1.0),
                            (CGPoint(x: rect.minX, y: rect.maxY), 1.0, -1.0), (CGPoint(x: rect.maxX, y: rect.maxY), -1.0, -1.0)] {
            p.move(to: CGPoint(x: c.x + l * dx, y: c.y))
            p.addLine(to: c)
            p.addLine(to: CGPoint(x: c.x, y: c.y + l * dy))
        }
        return p
    }
}

/// Move (drag inside) and resize (drag the corner knob) the active area.
struct TabletAreaEditor: View {
    @EnvironmentObject var model: ClientModel
    @ObservedObject var theme = Theme.shared
    @State private var area: TabletArea?
    @State private var dragStart: TabletArea?
    // Typed values in millimetres (nil = not edited yet: show the current area).
    @State private var mmW: Double?
    @State private var mmH: Double?
    @State private var mmX: Double?
    @State private var mmY: Double?
    @FocusState private var typing: Bool

    /// Points → millimetres on an 11" iPad Air (264 ppi, 2 px per point).
    private static let mmPerPoint = 2.0 / 264.0 * 25.4

    var body: some View {
        GeometryReader { g in
            let size = g.size
            let a = area ?? model.settings.tabletArea
            let r = a.rect(in: size)
            ZStack {
                Color.black.opacity(0.45)
                    .mask {
                        Rectangle().overlay(Rectangle().frame(width: r.width, height: r.height).position(x: r.midX, y: r.midY)
                            .blendMode(.destinationOut))
                            .compositingGroup()
                    }
                RoundedRectangle(cornerRadius: 4)
                    .fill(Brand.mint.opacity(0.08))
                    .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Brand.mint, style: StrokeStyle(lineWidth: 2, dash: [8, 6])))
                    .frame(width: r.width, height: r.height)
                    .position(x: r.midX, y: r.midY)
                    .gesture(DragGesture()
                        .onChanged { v in
                            let start = dragStart ?? a
                            dragStart = start
                            let sr = start.rect(in: size)
                            area = start.moved(toCenter: CGPoint(x: sr.midX + v.translation.width, y: sr.midY + v.translation.height), in: size)
                        }
                        .onEnded { _ in commit() })
                Circle()
                    .fill(Brand.mint)
                    .frame(width: 30, height: 30)
                    .overlay(Image(systemName: "arrow.up.left.and.arrow.down.right").font(.caption.bold()).foregroundStyle(Brand.slateDeep))
                    .contentShape(Circle().inset(by: -14))
                    .position(x: r.maxX, y: r.maxY)
                    .gesture(DragGesture()
                        .onChanged { v in
                            let start = dragStart ?? a
                            dragStart = start
                            area = resized(start, to: v.location, in: size)
                        }
                        .onEnded { _ in commit() })
                Text(String(format: "%.0f × %.0f mm", r.width * Self.mmPerPoint, r.height * Self.mmPerPoint))
                    .font(.callout.monospacedDigit().weight(.semibold))
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .tafelOverlayGlass(Capsule())
                    .position(x: r.midX, y: r.midY)
                    .allowsHitTesting(false)
                VStack(spacing: 10) {
                    toolbar
                    numbers(size)
                    Spacer()
                }
                .padding(.top, 14)
            }
        }
        .ignoresSafeArea()
    }

    private var toolbar: some View {
        HStack(spacing: 14) {
            Text(L("Aktiver Bereich")).font(.headline)
            Toggle(L("Seitenverhältnis wie Mac-Bildschirm"), isOn: $model.settings.tabletLockAspect)
                .toggleStyle(.switch).tint(Brand.mint).fixedSize()
            Button(L("Zurücksetzen")) {
                area = nil
                model.settings.tabletArea = TabletArea()
            }
            Button(L("Fertig")) {
                withAnimation(Brand.spring) { model.tabletEditing = false }
            }
            .buttonStyle(.borderedProminent).tint(Brand.mint).foregroundStyle(Brand.slateDeep)
        }
        .padding(.horizontal, 18).padding(.vertical, 10)
        .tafelOverlayGlass(Capsule())
    }

    /// Width, height and offset (from the top-left of the iPad) typed in millimetres.
    private func numbers(_ size: CGSize) -> some View {
        let r = (area ?? model.settings.tabletArea).rect(in: size)
        let cur = (w: r.width * Self.mmPerPoint, h: r.height * Self.mmPerPoint, x: r.minX * Self.mmPerPoint, y: r.minY * Self.mmPerPoint)
        return HStack(spacing: 12) {
            field(L("Breite"), $mmW, cur.w)
            Text("×").foregroundStyle(.secondary)
            field(L("Höhe"), $mmH, cur.h)
                .disabled(model.settings.tabletLockAspect)
                .opacity(model.settings.tabletLockAspect ? 0.5 : 1)
            Divider().frame(height: 22)
            field("X", $mmX, cur.x)
            field("Y", $mmY, cur.y)
            Button(L("Zentrieren")) {
                mmX = nil; mmY = nil
                apply(size, center: true)
            }
            Button(L("Übernehmen")) { apply(size, center: false) }
                .buttonStyle(.borderedProminent).tint(Brand.mint).foregroundStyle(Brand.slateDeep)
        }
        .font(.callout)
        .padding(.horizontal, 18).padding(.vertical, 8)
        .tafelOverlayGlass(Capsule())
    }

    private func field(_ label: String, _ value: Binding<Double?>, _ current: Double) -> some View {
        HStack(spacing: 4) {
            Text(label).foregroundStyle(.secondary)
            TextField(label, value: Binding(get: { value.wrappedValue ?? (current * 10).rounded() / 10 }, set: { value.wrappedValue = $0 }),
                      format: .number.precision(.fractionLength(0...1)))
                .keyboardType(.decimalPad)
                .focused($typing)
                .multilineTextAlignment(.trailing)
                .frame(width: 58)
                .padding(.horizontal, 6).padding(.vertical, 4)
                .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            Text("mm").foregroundStyle(.secondary)
        }
    }

    /// Applies the typed millimetres (clamped to the iPad), keeping the aspect lock.
    private func apply(_ size: CGSize, center: Bool) {
        typing = false
        let cur = (area ?? model.settings.tabletArea).rect(in: size)
        var w = (mmW.map { $0 / Self.mmPerPoint }) ?? cur.width
        var h = (mmH.map { $0 / Self.mmPerPoint }) ?? cur.height
        if model.settings.tabletLockAspect { h = w / model.tabletAspect }
        w = min(max(w, 40), size.width); h = min(max(h, 30), size.height)
        if model.settings.tabletLockAspect { let asp = model.tabletAspect; if w / h > asp { w = h * asp } else { h = w / asp } }
        var x = center ? (size.width - w) / 2 : ((mmX.map { $0 / Self.mmPerPoint }) ?? cur.minX)
        var y = center ? (size.height - h) / 2 : ((mmY.map { $0 / Self.mmPerPoint }) ?? cur.minY)
        x = min(max(x, 0), size.width - w); y = min(max(y, 0), size.height - h)
        area = nil
        model.settings.tabletArea = TabletArea(x: Double(x / size.width), y: Double(y / size.height),
                                               width: Double(w / size.width), height: Double(h / size.height))
        mmW = nil; mmH = nil; mmX = nil; mmY = nil
    }

    /// New area with its bottom-right corner at `p` (top-left stays), aspect-locked if wanted.
    private func resized(_ a: TabletArea, to p: CGPoint, in size: CGSize) -> TabletArea {
        let r = a.rect(in: size)
        var w = min(max(p.x - r.minX, 80), size.width - r.minX)
        var h = min(max(p.y - r.minY, 60), size.height - r.minY)
        if model.settings.tabletLockAspect {
            let asp = model.tabletAspect
            if w / h > asp { w = h * asp } else { h = w / asp }
        }
        return TabletArea(x: Double(r.minX / size.width), y: Double(r.minY / size.height),
                          width: Double(w / size.width), height: Double(h / size.height))
    }

    private func commit() {
        if let area { model.settings.tabletArea = area }
        area = nil
        dragStart = nil
    }
}
