import SwiftUI
import TafelKit

/// Tablet mode background: black like a screenless pen tablet, a fine dot grid and corner marks
/// for the active area (everything outside it is clamped to the area's edge).
struct TabletSurfaceView: View {
    @EnvironmentObject var model: ClientModel
    @ObservedObject var theme = Theme.shared

    var body: some View {
        GeometryReader { g in
            let r = model.tabletArea.rect(in: g.size)
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
        guard model.tabletLock else { return }
        let locked = model.tabletArea.locked(to: model.tabletAspect, in: size)
        let a = model.tabletArea
        if abs(locked.width - a.width) > 0.002 || abs(locked.height - a.height) > 0.002 { model.setTabletArea(locked) }
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
    // Millimetre fields: plain text (comma or point both work), one focus per field, refreshed
    // from the area only while you are not typing in them.
    private enum Field: Hashable, CaseIterable { case w, h, x, y }
    @FocusState private var focus: Field?
    @State private var text: [Field: String] = [:]
    /// The value a field showed before you tapped it (shown greyed while it is empty).
    @State private var before: [Field: String] = [:]
    @State private var viewSize: CGSize = .zero
    @State private var presetName = ""
    @State private var naming = false
    @FocusState private var nameFocus: Bool

    /// Points → millimetres on an 11" iPad Air (264 ppi, 2 px per point).
    private static let mmPerPoint = 2.0 / 264.0 * 25.4

    var body: some View {
        GeometryReader { g in
            let size = g.size
            let a = area ?? model.tabletArea
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
                    presets(size)
                    Spacer()
                }
                .padding(.top, 14)
                .onAppear { viewSize = size; fill(a, size) }
                .onChange(of: size) { viewSize = size; fill(area ?? model.tabletArea, size) }
                .onChange(of: area) { fill(area ?? model.tabletArea, size) }
                .onChange(of: model.tabletArea) { fill(area ?? model.tabletArea, size) }
                .onChange(of: model.tabletLock) { fill(area ?? model.tabletArea, size) }
                .onChange(of: focus) { old, new in
                    // Tapping a field empties it, so typing replaces the value instead of adding digits to it.
                    if let new { before[new] = text[new]; text[new] = "" }
                    // Left without typing: show the value again.
                    if let old, old != new, (text[old] ?? "").isEmpty { text[old] = before[old] }
                }
            }
        }
        .ignoresSafeArea()
    }

    private var toolbar: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 0) {
                Text(L("Aktiver Bereich")).font(.headline)
                if let p = model.activeAppPreset {
                    Text(L("Gilt jetzt für %@ (Preset „%@“)", p.appName ?? "", p.name)).font(.caption).foregroundStyle(Brand.mint)
                } else {
                    Text(L("Normaler Bereich (alle anderen Apps)")).font(.caption).foregroundStyle(.secondary)
                }
            }
            Toggle(L("Seitenverhältnis wie Mac-Bildschirm"), isOn: Binding(get: { model.tabletLock }, set: { model.setTabletLock($0) }))
                .toggleStyle(.switch).tint(Brand.mint).fixedSize()
            Button(L("Zurücksetzen")) {
                area = nil
                model.setTabletArea(TabletArea())
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
        HStack(spacing: 12) {
            field(L("Breite"), .w)
            Text("×").foregroundStyle(.secondary)
            field(L("Höhe"), .h)
                .disabled(model.tabletLock)
                .opacity(model.tabletLock ? 0.5 : 1)
            Divider().frame(height: 22)
            field("X", .x)
            field("Y", .y)
            Button(L("Zentrieren")) { apply(size, center: true) }
            Button(L("Übernehmen")) { apply(size, center: false) }
                .buttonStyle(.borderedProminent).tint(Brand.mint).foregroundStyle(Brand.slateDeep)
        }
        .font(.callout)
        .padding(.horizontal, 18).padding(.vertical, 8)
        .tafelOverlayGlass(Capsule())
    }

    private func field(_ label: String, _ f: Field) -> some View {
        HStack(spacing: 4) {
            Text(label).foregroundStyle(.secondary)
            TextField(before[f] ?? label, text: Binding(get: { text[f] ?? "" }, set: { new in
                text[f] = new
                // Aspect locked: the height follows the typed width right away.
                if f == .w, model.tabletLock, let w = Self.number(new) {
                    text[.h] = Self.format(w / model.tabletAspect)
                }
            }))
            .keyboardType(.decimalPad)
            .focused($focus, equals: f)
            .submitLabel(.done)
            .onSubmit { apply(viewSize, center: false) }
            .multilineTextAlignment(.trailing)
            .frame(width: 58)
            .padding(.horizontal, 6).padding(.vertical, 4)
            .background(.white.opacity(focus == f ? 0.16 : 0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            Text("mm").foregroundStyle(.secondary)
        }
    }

    /// Saved areas: tap to use, ✕ to delete; save the current area under a name.
    private func presets(_ size: CGSize) -> some View {
        let current = area ?? model.tabletArea
        return HStack(spacing: 8) {
            Text(L("Presets")).foregroundStyle(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    if model.settings.tabletPresets.isEmpty && !naming {
                        Text(L("Noch keine gespeichert")).foregroundStyle(.tertiary)
                    }
                    ForEach(model.settings.tabletPresets) { p in
                        let on = p.matches(current)
                        let r = p.area.rect(in: size)
                        HStack(spacing: 6) {
                            Button {
                                withAnimation(Brand.spring) { area = nil; model.applyTabletPreset(p) }
                            } label: {
                                VStack(alignment: .leading, spacing: 0) {
                                    Text(p.name).font(.callout.weight(.semibold)).lineLimit(1)
                                    Text(String(format: "%.0f × %.0f mm", r.width * Self.mmPerPoint, r.height * Self.mmPerPoint)
                                         + (p.appName.map { " · " + $0 } ?? ""))
                                        .font(.caption2.monospacedDigit()).opacity(0.75)
                                }
                            }
                            .buttonStyle(.plain)
                            // Bind to the app in front on the Mac (used automatically while it is in front).
                            if p.appBundleID != nil || model.frontApp != nil {
                                Button {
                                    withAnimation(Brand.spring) { model.bindTabletPreset(p, toFrontApp: p.appBundleID == nil) }
                                } label: {
                                    Image(systemName: p.appBundleID != nil ? "link.circle.fill" : "link").font(.caption.bold())
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(p.appBundleID != nil ? L("Von der App lösen") : L("An %@ binden", model.frontApp?.name ?? ""))
                            }
                            Button {
                                withAnimation(Brand.spring) { model.settings.tabletPresets.removeAll { $0.id == p.id } }
                            } label: {
                                Image(systemName: "xmark").font(.caption2.bold()).opacity(0.7)
                            }
                            .buttonStyle(.plain)
                        }
                        .foregroundStyle(on ? Brand.slateDeep : .primary)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(on ? AnyShapeStyle(Brand.mint) : AnyShapeStyle(Color.white.opacity(0.1)), in: Capsule())
                    }
                }
            }
            .frame(maxWidth: 520)
            if naming {
                TextField(L("Name"), text: $presetName)
                    .focused($nameFocus)
                    .submitLabel(.done)
                    .onSubmit(save)
                    .frame(width: 150)
                    .padding(.horizontal, 8).padding(.vertical, 5)
                    .background(.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                Button(L("Speichern"), action: save)
                    .buttonStyle(.borderedProminent).tint(Brand.mint).foregroundStyle(Brand.slateDeep)
                Button(L("Abbrechen")) { naming = false; presetName = "" }
            } else {
                Button {
                    commit()
                    naming = true
                    nameFocus = true
                } label: {
                    Label(L("Als Preset speichern"), systemImage: "plus")
                }
            }
        }
        .font(.callout)
        .padding(.horizontal, 18).padding(.vertical, 8)
        .tafelOverlayGlass(Capsule())
    }

    private func save() {
        commit()
        withAnimation(Brand.spring) { model.saveTabletPreset(named: presetName) }
        presetName = ""
        naming = false
        nameFocus = false
    }

    static func number(_ s: String) -> Double? {
        Double(s.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: "."))
    }

    static func format(_ v: Double) -> String {
        let r = (v * 10).rounded() / 10
        return r == r.rounded() ? String(Int(r)) : String(format: "%.1f", r)
    }

    /// Shows the area in the fields – except in the field you are typing in.
    private func fill(_ a: TabletArea, _ size: CGSize) {
        guard size.width > 0 else { return }
        let r = a.rect(in: size)
        let values: [Field: CGFloat] = [.w: r.width, .h: r.height, .x: r.minX, .y: r.minY]
        for (f, v) in values where focus != f {
            text[f] = Self.format(Double(v) * Self.mmPerPoint)
        }
    }

    /// Applies the typed millimetres (clamped to the iPad), keeping the aspect lock.
    private func apply(_ size: CGSize, center: Bool) {
        focus = nil
        guard size.width > 0 else { return }
        let cur = (area ?? model.tabletArea).rect(in: size)
        func pt(_ f: Field, _ fallback: CGFloat) -> CGFloat {
            let typed = (text[f] ?? "").isEmpty ? before[f] ?? "" : text[f] ?? ""
            return Self.number(typed).map { CGFloat($0 / Self.mmPerPoint) } ?? fallback
        }
        var w = pt(.w, cur.width)
        var h = model.tabletLock ? w / model.tabletAspect : pt(.h, cur.height)
        w = min(max(w, 40), size.width); h = min(max(h, 30), size.height)
        if model.tabletLock { let asp = model.tabletAspect; if w / h > asp { w = h * asp } else { h = w / asp } }
        var x = center ? (size.width - w) / 2 : pt(.x, cur.minX)
        var y = center ? (size.height - h) / 2 : pt(.y, cur.minY)
        x = min(max(x, 0), size.width - w); y = min(max(y, 0), size.height - h)
        area = nil
        let new = TabletArea(x: Double(x / size.width), y: Double(y / size.height),
                             width: Double(w / size.width), height: Double(h / size.height))
        model.setTabletArea(new)
        before = [:]
        fill(new, size)   // show what was actually applied (after clamping)
    }

    /// New area with its bottom-right corner at `p` (top-left stays), aspect-locked if wanted.
    private func resized(_ a: TabletArea, to p: CGPoint, in size: CGSize) -> TabletArea {
        let r = a.rect(in: size)
        var w = min(max(p.x - r.minX, 80), size.width - r.minX)
        var h = min(max(p.y - r.minY, 60), size.height - r.minY)
        if model.tabletLock {
            let asp = model.tabletAspect
            if w / h > asp { w = h * asp } else { h = w / asp }
        }
        return TabletArea(x: Double(r.minX / size.width), y: Double(r.minY / size.height),
                          width: Double(w / size.width), height: Double(h / size.height))
    }

    private func commit() {
        if let area { model.setTabletArea(area) }
        area = nil
        dragStart = nil
    }
}
