import SwiftUI
import TafelKit

/// Only for the orientation lock: SwiftUI has no API for the allowed orientations.
final class AppDelegate: NSObject, UIApplicationDelegate {
    nonisolated(unsafe) static var allowed: UIInterfaceOrientationMask = .all
    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        Self.allowed
    }
}

@main
struct TafelApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = ClientModel.shared

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
    @State private var showCheatSheet = false
    @State private var showWhatsNew = WhatsNewView.shouldShow
    @State private var showStatus = false

    private var reconnecting: Bool {
        if case .reconnecting = model.phase { return true }
        return false
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if model.demoMode {
                DemoView()
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
                    .zIndex(20)
            } else if !model.onboardingDone {
                OnboardingView()
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            } else if model.phase.showsCanvas {
                if model.tabletModeActive {
                    TabletSurfaceView()
                        .transition(.opacity)
                }
                CanvasRepresentable(model: model)
                    .grayscale(model.grayscale && !model.tabletModeActive ? 1 : 0)
                    .ignoresSafeArea()
                    .transition(.opacity)
                ReferenceOverlay(ref: model.reference)
                    .transition(.opacity)
                if !model.tabletModeActive {
                    PaletteOverlay(palette: model.palette, send: { model.palettePointer($0) }, close: { model.removePalette() })
                        .zIndex(8)
                }
                overlay
                    .transition(.opacity)
                if model.tabletEditing && model.tabletModeActive {
                    TabletAreaEditor()
                        .transition(.opacity)
                        .zIndex(9)
                }
                if let c = model.radialCenter {
                    RadialMenuView(center: c)
                        .zIndex(10)
                }
                if let img = model.screenshot {
                    ScreenshotView(image: img)
                        .transition(.opacity.combined(with: .scale(scale: 0.97)))
                        .zIndex(15)
                }
            } else {
                ConnectView()
                    .transition(.opacity.combined(with: .scale(scale: 1.03)))
            }
        }
        .animation(.easeInOut(duration: 0.35), value: model.phase.showsCanvas)
        .animation(.easeInOut(duration: 0.3), value: model.settings.tabletMode)
        .animation(Brand.spring, value: model.radialCenter != nil)
        .sensoryFeedback(.pathComplete, trigger: model.radialCenter == nil) { old, new in !old && new }
        .animation(.easeInOut(duration: 0.45), value: model.onboardingDone)
        .animation(Brand.spring, value: model.demoMode)
        .animation(Brand.spring, value: model.screenshot != nil)
        .id(l10n.language)   // re-render every text when the language changes
        .sheet(isPresented: $showSettings) {
            SettingsView().environmentObject(model)
                .presentationBackground { ThemeBackground() }
        }
        .sheet(isPresented: $showWhatsNew, onDismiss: WhatsNewView.markSeen) {
            WhatsNewView().presentationBackground { ThemeBackground() }
        }
        .sheet(isPresented: $showCheatSheet) {
            CheatSheetView().environmentObject(model)
                .presentationBackground { ThemeBackground() }
        }
    }

    private func undoButton(_ symbol: String, _ label: String, _ action: @escaping () -> Void) -> some View {
        UltraRoundButton(symbol, label: label, size: 50, action: action)
    }

    private var overlay: some View {
        ZStack {
            if model.settings.undoButtons && !model.tabletModeActive && !model.settings.viewOnly {
                VStack {
                    Spacer()
                    HStack(spacing: 12) {
                        if !model.settings.shortcutBarOnRight { Spacer() }
                        undoButton("arrow.uturn.backward", L("Widerrufen")) { model.trigger(.undo) }
                        undoButton("arrow.uturn.forward", L("Wiederholen")) { model.trigger(.redo) }
                        if model.settings.shortcutBarOnRight { Spacer() }
                    }
                    .padding(.horizontal, 18).padding(.bottom, 18)
                }
            }
            if model.settings.showShortcutBar && !model.tabletModeActive && !model.settings.viewOnly {
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
                    UltraRoundButton(model.commandOpen ? "xmark" : "square.grid.2x2.fill",
                                     label: model.commandOpen ? L("Menü schließen") : L("Menü"), size: 40) {
                        withAnimation(Ultra.smooth) { model.commandOpen.toggle() }
                    }
                }
                if let t = model.toast {
                    Text(t.text)
                        .font(.callout.weight(.semibold))
                        .padding(.horizontal, 18).padding(.vertical, 11)
                        .ultraPanel(Capsule())
                        .allowsHitTesting(false)
                        .transition(.move(edge: .top).combined(with: .opacity).combined(with: .scale(scale: 0.92)))
                        .id(t.text)
                }
                if (model.localZoom > 1.01 || model.localAngle != 0) && model.settings.zoomMethod == .localView {
                    Button {
                        model.localZoomResets += 1
                    } label: {
                        Label((model.localAngle != 0 ? "\(model.localAngle)° · " : "") + L("%d %% · Zurücksetzen", Int((model.localZoom * 100).rounded())),
                              systemImage: model.localAngle != 0 ? "rotate.right" : "arrow.up.left.and.down.right.magnifyingglass")
                            .font(.callout.weight(.semibold).monospacedDigit())
                            .padding(.horizontal, 14).padding(.vertical, 9)
                            .ultraPanel(Capsule(), shadow: false)
                    }
                    .buttonStyle(UltraPress())
                    .transition(.move(edge: .top).combined(with: .opacity))
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
            if model.commandOpen {
                // No backdrop: the next touch on the canvas closes it (see CanvasView.chromeOpen).
                GeometryReader { g in
                    VStack {
                        HStack {
                            Spacer()
                            CommandCenter(
                                close: { withAnimation(Ultra.smooth) { model.commandOpen = false } },
                                toggleStatus: { withAnimation(Ultra.smooth) { showStatus.toggle() } }, showStatus: showStatus,
                                openSettings: { showSettings = true },
                                openCheatSheet: { showCheatSheet = true },
                                maxHeight: max(g.size.height - 16, 200))
                        }
                        Spacer()
                    }
                }
                .padding(.top, 58).padding(.trailing, 10)
                .transition(.scale(scale: 0.86, anchor: .topTrailing).combined(with: .opacity))
            }
        }
        .animation(Brand.spring, value: reconnecting)
        .animation(Ultra.smooth, value: model.commandOpen)
        .animation(Brand.spring, value: model.scrubSteps != nil)
        .animation(Brand.spring, value: model.toast)
        .animation(Brand.spring, value: showStatus || model.showStatusOverlay)
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
                    .accessibilityLabel(usb ? L("USB-Kabel") : L("WLAN"))
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
                        model.run(b)
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
                    Button {
                        withAnimation(Brand.spring) { model.demoMode = true }
                    } label: {
                        Label(L("Ohne Mac ausprobieren (Demo)"), systemImage: "sparkles")
                    }
                    .buttonStyle(.bordered)
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
