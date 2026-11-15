import SwiftUI
import TafelKit

@main
struct TafelApp: App {
    @StateObject private var model = ClientModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .preferredColorScheme(.dark)
                .statusBarHidden(true)
                .persistentSystemOverlays(.hidden)
                .defersSystemGestures(on: .all)
        }
    }
}

struct RootView: View {
    /// Redraw when the colours change.
    @ObservedObject var theme = Theme.shared
    @EnvironmentObject var model: ClientModel
    @ObservedObject private var l10n = L10n.shared
    @State private var showSettings = false
    @State private var showStatus = false

    private var reconnecting: Bool {
        if case .reconnecting = model.phase { return true }
        return false
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if !model.onboardingDone {
                OnboardingView()
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            } else if model.phase.showsCanvas {
                CanvasRepresentable(model: model)
                    .ignoresSafeArea()
                    .transition(.opacity)
                overlay
                    .transition(.opacity)
                if let c = model.radialCenter {
                    RadialMenuView(center: c)
                        .zIndex(10)
                }
            } else {
                ConnectView()
                    .transition(.opacity.combined(with: .scale(scale: 1.03)))
            }
        }
        .animation(.easeInOut(duration: 0.35), value: model.phase.showsCanvas)
        .animation(Brand.spring, value: model.radialCenter != nil)
        .sensoryFeedback(.pathComplete, trigger: model.radialCenter == nil) { old, new in !old && new }
        .animation(.easeInOut(duration: 0.45), value: model.onboardingDone)
        .id(l10n.language)   // re-render every text when the language changes
        .sheet(isPresented: $showSettings) {
            SettingsView().environmentObject(model)
        }
    }

    private var overlay: some View {
        ZStack {
            if model.settings.showShortcutBar {
                HStack {
                    if model.settings.shortcutBarOnRight { Spacer() }
                    ShortcutBar()
                    if !model.settings.shortcutBarOnRight { Spacer() }
                }
                .padding(.horizontal, 8)
                .transition(.move(edge: .leading).combined(with: .opacity))
            }
            VStack(spacing: 10) {
                HStack(alignment: .top) {
                    Spacer()
                    if showStatus || model.showStatusOverlay {
                        StatusPill()
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                    }
                    Menu {
                        SourceMenu()
                        if let app = model.frontApp {
                            Button {
                                model.toggleGameMode()
                            } label: {
                                Label(model.gameModeActive ? L("Spielmodus für %@ aus", app.name) : L("Spielmodus für %@", app.name),
                                      systemImage: "gamecontroller")
                            }
                        }
                        Divider()
                        Button {
                            showStatus.toggle()
                        } label: {
                            Label(showStatus ? L("Status ausblenden") : L("Status anzeigen"), systemImage: "gauge.with.dots.needle.33percent")
                        }
                        Button {
                            model.showKeyboard.toggle()
                        } label: {
                            Label(model.showKeyboard ? L("Bildschirmtastatur ausblenden") : L("Bildschirmtastatur"), systemImage: "keyboard")
                        }
                        Button {
                            showSettings = true
                        } label: {
                            Label(L("Einstellungen …"), systemImage: "gearshape")
                        }
                        Divider()
                        Button(role: .destructive) {
                            model.disconnect()
                        } label: {
                            Label(L("Trennen"), systemImage: "xmark.circle")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 15, weight: .semibold))
                            .frame(width: 36, height: 36)
                            .tafelGlass(Circle())
                            .opacity(0.7)
                    }
                }
                if let n = model.scrubSteps {
                    ScrubPill(steps: n)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                if reconnecting {
                    ReconnectBanner()
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                Spacer()
            }
            .padding(10)
        }
        .animation(Brand.spring, value: reconnecting)
        .animation(Brand.spring, value: model.scrubSteps != nil)
        .animation(Brand.spring, value: showStatus || model.showStatusOverlay)
    }
}

/// Source picker in the … menu: what the Mac streams, switched from the iPad.
private struct SourceMenu: View {
    @EnvironmentObject var model: ClientModel

    /// Mode names from the Mac, shown in the iPad's language.
    private func title(_ o: SourceOption) -> String {
        switch o.id {
        case "display": return L("Ganzer Bildschirm")
        case "second-screen": return L("Zweiter Bildschirm")
        case "region": return L("iPad-Ausschnitt")
        case "window": return L("Fenster")
        default: return o.title
        }
    }

    private func icon(_ id: String) -> String {
        switch id {
        case "display": return "display"
        case "second-screen": return "rectangle.on.rectangle"
        case "region": return "ipad.landscape"
        default: return "macwindow"
        }
    }

    var body: some View {
        if let l = model.sourceList {
            Menu {
                ForEach(l.modes.filter { $0.id != "window" }) { m in
                    Button {
                        model.selectSource(SourceSelection(mode: m.id))
                    } label: {
                        Label(title(m), systemImage: l.mode == m.id ? "checkmark" : icon(m.id))
                    }
                    .disabled(!m.available)
                }
                Menu {
                    ForEach(l.windows) { w in
                        Button {
                            model.selectSource(SourceSelection(mode: "window", window: w.id))
                        } label: {
                            if l.mode == "window" && l.selectedWindow == w.id { Label(w.title, systemImage: "checkmark") } else { Text(w.title) }
                        }
                    }
                    Divider()
                    Button(L("Fensterliste aktualisieren")) { model.selectSource(SourceSelection(refresh: true)) }
                } label: {
                    Label(L("Fenster"), systemImage: l.mode == "window" ? "checkmark" : "macwindow")
                }
                if l.displays.count > 1 {
                    Divider()
                    ForEach(l.displays) { d in
                        Button {
                            model.selectSource(SourceSelection(display: d.id))
                        } label: {
                            if l.selectedDisplay == d.id { Label(d.title, systemImage: "checkmark") } else { Text(d.title) }
                        }
                    }
                }
            } label: {
                Label(L("Quelle"), systemImage: "rectangle.on.rectangle.angled")
            }
        }
    }
}

/// Undo scrub feedback: "↶ 3" while dragging left, "↷ 2" right.
private struct ScrubPill: View {
    /// Redraw when the colours change.
    @ObservedObject var theme = Theme.shared
    let steps: Int
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: steps < 0 ? "arrow.uturn.backward" : steps > 0 ? "arrow.uturn.forward" : "arrow.left.and.right")
            Text(steps == 0 ? L("Ziehen: links Undo, rechts Redo") : "\(abs(steps))")
                .monospacedDigit()
                .contentTransition(.numericText())
        }
        .font(.callout.weight(.semibold))
        .padding(.horizontal, 16).padding(.vertical, 10)
        .tafelGlass(Capsule())
        .animation(Brand.spring, value: steps)
        .allowsHitTesting(false)
    }
}

private struct ReconnectBanner: View {
    /// Redraw when the colours change.
    @ObservedObject var theme = Theme.shared
    var body: some View {
        HStack(spacing: 10) {
            ProgressView().tint(Brand.mint)
            Text(L("Verbindung unterbrochen – verbinde neu …"))
                .font(.callout.weight(.medium))
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .tafelGlass(Capsule())
        .allowsHitTesting(false)
    }
}

struct StatusPill: View {
    /// Redraw when the colours change.
    @ObservedObject var theme = Theme.shared
    @EnvironmentObject var model: ClientModel

    var body: some View {
        HStack(spacing: 10) {
            if let t = model.timing {
                let usb = t.link.hasPrefix("USB")
                Image(systemName: usb ? "cable.connector" : "wifi")
                    .foregroundStyle(usb ? Brand.mint : .orange)
                    .contentTransition(.symbolEffect(.replace))
                metric(t.rttMs, "ms RTT")
                if let age = t.frameAgeMs { metric(age, L("ms Bild")) }
                metric(t.fps, "fps")
            } else {
                ProgressView().controlSize(.mini)
                Text(L("misst …"))
            }
        }
        .font(.caption.monospacedDigit())
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .tafelGlass(Capsule())
    }

    private func metric(_ v: Double, _ unit: String) -> some View {
        HStack(spacing: 3) {
            Text("\(Int(v.rounded()))")
                .fontWeight(.semibold)
                .contentTransition(.numericText(value: v))
                .animation(.snappy, value: Int(v.rounded()))
            Text(unit).foregroundStyle(.secondary)
        }
    }
}

struct ShortcutBar: View {
    /// Redraw when the colours change.
    @ObservedObject var theme = Theme.shared
    @EnvironmentObject var model: ClientModel

    var body: some View {
        VStack(spacing: 6) {
            ForEach(model.currentBar) { b in
                if let key = b.hold {
                    HoldButton(title: b.title, key: key)
                } else {
                    Button {
                        model.trigger(.shortcut(b.shortcut))
                    } label: {
                        barLabel(b.title, active: false)
                    }
                    .buttonStyle(PressScale())
                }
            }
        }
        .opacity(0.85)
        .animation(Brand.spring, value: model.currentBar.map(\.id))
    }
}

func barLabel(_ title: String, active: Bool) -> some View {
    Text(title)
        .font(.caption2.weight(.semibold))
        .lineLimit(1)
        .frame(width: 60, height: 36)
        .foregroundStyle(active ? Brand.slateDeep : .primary)
        .background(active ? AnyShapeStyle(Brand.mint) : AnyShapeStyle(Color.clear), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .tafelGlass(RoundedRectangle(cornerRadius: 10, style: .continuous))
}

/// Holds a key (⇧, ⌥, ⌘, ⌃, Space) down while the finger rests on it – works while the Pencil
/// draws with the other hand.
struct HoldButton: View {
    @EnvironmentObject var model: ClientModel
    let title: String
    let key: HoldKey
    @State private var down = false

    var body: some View {
        barLabel(title, active: down)
            .scaleEffect(down ? 0.92 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: down)
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { _ in if !down { down = true; model.hold(key, down: true) } }
                .onEnded { _ in down = false; model.hold(key, down: false) })
            .onDisappear { if down { down = false; model.hold(key, down: false) } }
    }
}

/// Springy press feedback.
struct PressScale: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.88 : 1)
            .brightness(configuration.isPressed ? 0.15 : 0)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

// MARK: - Start screen

struct ConnectView: View {
    /// Redraw when the colours change.
    @ObservedObject var theme = Theme.shared
    @EnvironmentObject var model: ClientModel
    @State private var pairTarget: DiscoveredHost?
    @State private var appeared = false

    private var searching: Bool {
        if case .idle = model.phase { return model.discovered.filter { model.isPaired($0) }.isEmpty }
        return false
    }

    var body: some View {
        ZStack {
            ThemeBackground().ignoresSafeArea()
            ScrollView {
                VStack(spacing: 26) {
                    header
                    status
                    pairedSection
                    pairSection
                    Text(L("Nur Geräte mit dem einmaligen Code vom Mac werden gekoppelt. Verbindungen laufen verschlüsselt und direkt – per Kabel oder im lokalen Netz, ohne Server, Konto oder Cloud."))
                        .font(.footnote).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 520)
                }
                .frame(maxWidth: 640)
                .padding(.horizontal, 24)
                .padding(.vertical, 48)
                .frame(maxWidth: .infinity)
            }
        }
        .animation(Brand.spring, value: model.discovered.map(\.id))
        .animation(Brand.spring, value: model.pairable.map(\.id))
        .animation(Brand.spring, value: model.phase)
        .sheet(item: $pairTarget) { host in
            PairingSheet(host: host).environmentObject(model)
        }
        .onAppear { withAnimation(.spring(response: 0.7, dampingFraction: 0.75).delay(0.05)) { appeared = true } }
    }

    private var header: some View {
        VStack(spacing: 14) {
            ZStack {
                PulseRings(color: Brand.mint, active: searching)
                    .frame(width: 120, height: 120)
                TafelMark()
                    .frame(width: 96, height: 96)
                    .shadow(color: Brand.mint.opacity(0.35), radius: 24)
            }
            .scaleEffect(appeared ? 1 : 0.7)
            .opacity(appeared ? 1 : 0)
            Text("UniversePen")
                .font(.system(size: 44, weight: .bold, design: .rounded))
            Text(L("Dein iPad als Zeichendisplay für den Mac"))
                .font(.title3).foregroundStyle(.secondary)
        }
        .offset(y: appeared ? 0 : 16)
    }

    @ViewBuilder private var status: some View {
        switch model.phase {
        case .connecting(let name):
            StatusCard(symbol: nil, tint: Brand.mint, text: L("Verbinde mit %@ …", name))
                .transition(.scale(scale: 0.95).combined(with: .opacity))
        case .failed(let msg):
            VStack(spacing: 12) {
                Label(msg, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.leading)
                Button {
                    model.retry()
                } label: {
                    Label(L("Erneut versuchen"), systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderedProminent).tint(Brand.mint.opacity(0.85))
            }
            .tafelCard()
            .transition(.scale(scale: 0.95).combined(with: .opacity))
        default:
            if searching && !model.paired.isEmpty {
                StatusCard(symbol: "magnifyingglass", tint: .secondary, text: L("Suche deinen Mac … UniversePen Host muss laufen."))
                    .transition(.opacity)
            }
        }
    }

    private var pairedSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !model.paired.isEmpty {
                Text(L("Deine Macs")).font(.headline).foregroundStyle(Brand.mintBright)
            }
            ForEach(model.paired) { p in
                let host = model.discovered.first { $0.hostID == p.id }
                HostCard(name: p.name, host: host) {
                    if let host { model.connect(host) }
                }
                .contextMenu {
                    Button(role: .destructive) { model.forget(p) } label: { Label(L("Kopplung entfernen"), systemImage: "trash") }
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    private var pairSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L("Neu koppeln")).font(.headline).foregroundStyle(Brand.mintBright)
            if model.pairable.isEmpty {
                HStack(spacing: 12) {
                    Image(systemName: "laptopcomputer.and.arrow.down")
                        .font(.title2).foregroundStyle(.secondary)
                    Text(L("Am Mac in UniversePen Host „iPad koppeln …“ wählen – der Mac erscheint dann hier."))
                        .foregroundStyle(.secondary)
                }
                .tafelCard()
            }
            ForEach(model.pairable) { h in
                Button {
                    pairTarget = h
                } label: {
                    HStack(spacing: 14) {
                        Image(systemName: "link.badge.plus")
                            .font(.title2).foregroundStyle(Brand.mint)
                            .symbolEffect(.pulse, options: .repeating)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(h.name).font(.headline)
                            Text(L("bereit zum Koppeln")).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                    }
                    .tafelCard()
                }
                .buttonStyle(PressScale())
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }
}

private struct StatusCard: View {
    let symbol: String?
    let tint: Color
    let text: String
    var body: some View {
        HStack(spacing: 12) {
            if let symbol {
                Image(systemName: symbol).foregroundStyle(tint)
                    .symbolEffect(.pulse, options: .repeating)
            } else {
                ProgressView().tint(tint)
            }
            Text(text)
        }
        .tafelCard()
    }
}

private struct HostCard: View {
    /// Redraw when the colours change.
    @ObservedObject var theme = Theme.shared
    let name: String
    let host: DiscoveredHost?
    let connect: () -> Void

    var body: some View {
        let reachable = host != nil
        let cable = !(host?.cableInterfaces.isEmpty ?? true)
        Button(action: connect) {
            HStack(spacing: 16) {
                ZStack {
                    Circle().fill(reachable ? Brand.mint.opacity(0.18) : .white.opacity(0.06))
                    Image(systemName: "laptopcomputer")
                        .font(.title2)
                        .foregroundStyle(reachable ? Brand.mint : .secondary)
                }
                .frame(width: 52, height: 52)
                VStack(alignment: .leading, spacing: 4) {
                    Text(name).font(.headline)
                    HStack(spacing: 6) {
                        Circle().fill(reachable ? Brand.mint : .gray).frame(width: 7, height: 7)
                        Text(reachable ? (cable ? L("erreichbar · per Kabel") : L("erreichbar · WLAN")) : L("nicht gefunden"))
                            .font(.caption).foregroundStyle(.secondary)
                            .contentTransition(.opacity)
                    }
                }
                Spacer()
                if reachable {
                    Text(L("Verbinden"))
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(Brand.slateDeep)
                        .padding(.horizontal, 16).padding(.vertical, 9)
                        .background(Brand.mint, in: Capsule())
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .tafelCard()
        }
        .buttonStyle(PressScale())
        .disabled(!reachable)
    }
}

// MARK: - Pairing sheet

private struct PairingSheet: View {
    /// Redraw when the colours change.
    @ObservedObject var theme = Theme.shared
    @EnvironmentObject var model: ClientModel
    @Environment(\.dismiss) private var dismiss
    let host: DiscoveredHost
    @State private var code = ""
    @FocusState private var focused: Bool
    @State private var shake = 0

    private var normalized: String? { PairingCode.normalize(code) }

    var body: some View {
        VStack(spacing: 22) {
            Image(systemName: "lock.laptopcomputer")
                .font(.system(size: 44))
                .foregroundStyle(Brand.mint)
                .symbolEffect(.bounce, value: model.pairingBusy)
            VStack(spacing: 6) {
                Text(L("Mit %@ koppeln", host.name)).font(.title2.weight(.semibold))
                Text(L("Gib den 12-stelligen Code ein, den UniversePen Host auf dem Mac zeigt."))
                    .foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            TextField("XXXX-XXXX-XXXX", text: $code)
                .font(.system(size: 30, weight: .semibold, design: .monospaced))
                .multilineTextAlignment(.center)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .focused($focused)
                .padding(.vertical, 14)
                .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(normalized != nil ? Brand.mint : .white.opacity(0.1), lineWidth: 1.5))
                .modifier(Shake(animatableData: CGFloat(shake)))
                .onSubmit(submit)
            if let e = model.pairingError {
                Label(e, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout).foregroundStyle(.orange)
                    .transition(.opacity)
            }
            HStack(spacing: 12) {
                Button(L("Abbrechen")) { dismiss() }
                    .buttonStyle(.bordered)
                Button(action: submit) {
                    HStack(spacing: 8) {
                        if model.pairingBusy { ProgressView().tint(Brand.slateDeep) }
                        Text(L("Koppeln")).fontWeight(.semibold)
                    }
                    .frame(minWidth: 120)
                }
                .buttonStyle(.borderedProminent)
                .tint(Brand.mint)
                .foregroundStyle(Brand.slateDeep)
                .disabled(normalized == nil || model.pairingBusy)
            }
            .controlSize(.large)
        }
        .padding(32)
        .frame(maxWidth: 520)
        .presentationDetents([.medium])
        .presentationBackground { ThemeBackground() }
        .animation(Brand.spring, value: model.pairingError)
        .animation(Brand.spring, value: normalized != nil)
        .onAppear {
            model.pairingError = nil
            focused = true
        }
        .onChange(of: model.pairingBusy) { _, busy in
            guard !busy else { return }
            if model.pairingError == nil {
                dismiss()
            } else {
                withAnimation(.default) { shake += 1 }
            }
        }
    }

    private func submit() {
        guard normalized != nil, !model.pairingBusy else { return }
        model.pair(with: host, code: code)
    }
}

/// Horizontal shake for a wrong code.
private struct Shake: GeometryEffect {
    var animatableData: CGFloat
    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: 10 * sin(animatableData * .pi * 4), y: 0))
    }
}
