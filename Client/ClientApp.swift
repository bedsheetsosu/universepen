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
    @EnvironmentObject var model: ClientModel
    @State private var showSettings = false
    @State private var showStatus = false

    private var reconnecting: Bool {
        if case .reconnecting = model.phase { return true }
        return false
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if model.phase.showsCanvas {
                CanvasRepresentable(model: model)
                    .ignoresSafeArea()
                    .transition(.opacity)
                overlay
                    .transition(.opacity)
            } else {
                ConnectView()
                    .transition(.opacity.combined(with: .scale(scale: 1.03)))
            }
        }
        .animation(.easeInOut(duration: 0.35), value: model.phase.showsCanvas)
        .sheet(isPresented: $showSettings) {
            SettingsView().environmentObject(model)
        }
    }

    private var overlay: some View {
        ZStack {
            if model.settings.showShortcutBar {
                HStack {
                    ShortcutBar()
                    Spacer()
                }
                .padding(.leading, 8)
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
                        Button {
                            showStatus.toggle()
                        } label: {
                            Label(showStatus ? "Status ausblenden" : "Status anzeigen", systemImage: "gauge.with.dots.needle.33percent")
                        }
                        Button {
                            model.showKeyboard.toggle()
                        } label: {
                            Label(model.showKeyboard ? "Bildschirmtastatur ausblenden" : "Bildschirmtastatur", systemImage: "keyboard")
                        }
                        Button {
                            showSettings = true
                        } label: {
                            Label("Einstellungen …", systemImage: "gearshape")
                        }
                        Divider()
                        Button(role: .destructive) {
                            model.disconnect()
                        } label: {
                            Label("Trennen", systemImage: "xmark.circle")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 15, weight: .semibold))
                            .frame(width: 36, height: 36)
                            .tafelGlass(Circle())
                            .opacity(0.7)
                    }
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
        .animation(Brand.spring, value: showStatus || model.showStatusOverlay)
    }
}

private struct ReconnectBanner: View {
    var body: some View {
        HStack(spacing: 10) {
            ProgressView().tint(Brand.mint)
            Text("Verbindung unterbrochen – verbinde neu …")
                .font(.callout.weight(.medium))
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .tafelGlass(Capsule())
        .allowsHitTesting(false)
    }
}

struct StatusPill: View {
    @EnvironmentObject var model: ClientModel

    var body: some View {
        HStack(spacing: 10) {
            if let t = model.timing {
                let usb = t.link.hasPrefix("USB")
                Image(systemName: usb ? "cable.connector" : "wifi")
                    .foregroundStyle(usb ? Brand.mint : .orange)
                    .contentTransition(.symbolEffect(.replace))
                metric(t.rttMs, "ms RTT")
                if let age = t.frameAgeMs { metric(age, "ms Bild") }
                metric(t.fps, "fps")
            } else {
                ProgressView().controlSize(.mini)
                Text("misst …")
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
    @EnvironmentObject var model: ClientModel

    var body: some View {
        VStack(spacing: 6) {
            ForEach(model.settings.shortcutBar) { b in
                Button {
                    model.trigger(.shortcut(b.shortcut))
                } label: {
                    Text(b.title)
                        .font(.caption2.weight(.semibold))
                        .lineLimit(1)
                        .frame(width: 60, height: 36)
                        .tafelGlass(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(PressScale())
            }
        }
        .opacity(0.85)
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
    @EnvironmentObject var model: ClientModel
    @State private var pairTarget: DiscoveredHost?
    @State private var appeared = false

    private var searching: Bool {
        if case .idle = model.phase { return model.discovered.filter { model.isPaired($0) }.isEmpty }
        return false
    }

    var body: some View {
        ZStack {
            Brand.background.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 26) {
                    header
                    status
                    pairedSection
                    pairSection
                    Text("Nur Geräte mit dem einmaligen Code vom Mac werden gekoppelt. Verbindungen laufen verschlüsselt und direkt – per Kabel oder im lokalen Netz, ohne Server, Konto oder Cloud.")
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
            Text("Tafel")
                .font(.system(size: 44, weight: .bold, design: .rounded))
            Text("Dein iPad als Zeichendisplay für den Mac")
                .font(.title3).foregroundStyle(.secondary)
        }
        .offset(y: appeared ? 0 : 16)
    }

    @ViewBuilder private var status: some View {
        switch model.phase {
        case .connecting(let name):
            StatusCard(symbol: nil, tint: Brand.mint, text: "Verbinde mit \(name) …")
                .transition(.scale(scale: 0.95).combined(with: .opacity))
        case .failed(let msg):
            VStack(spacing: 12) {
                Label(msg, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.leading)
                Button {
                    model.retry()
                } label: {
                    Label("Erneut versuchen", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderedProminent).tint(Brand.mint.opacity(0.85))
            }
            .tafelCard()
            .transition(.scale(scale: 0.95).combined(with: .opacity))
        default:
            if searching && !model.paired.isEmpty {
                StatusCard(symbol: "magnifyingglass", tint: .secondary, text: "Suche deinen Mac … Tafel Host muss laufen.")
                    .transition(.opacity)
            }
        }
    }

    private var pairedSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !model.paired.isEmpty {
                Text("Deine Macs").font(.headline).foregroundStyle(Brand.mintBright)
            }
            ForEach(model.paired) { p in
                let host = model.discovered.first { $0.hostID == p.id }
                HostCard(name: p.name, host: host) {
                    if let host { model.connect(host) }
                }
                .contextMenu {
                    Button(role: .destructive) { model.forget(p) } label: { Label("Kopplung entfernen", systemImage: "trash") }
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    private var pairSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Neu koppeln").font(.headline).foregroundStyle(Brand.mintBright)
            if model.pairable.isEmpty {
                HStack(spacing: 12) {
                    Image(systemName: "laptopcomputer.and.arrow.down")
                        .font(.title2).foregroundStyle(.secondary)
                    Text("Am Mac in Tafel Host „iPad koppeln …“ wählen – der Mac erscheint dann hier.")
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
                            Text("bereit zum Koppeln").font(.caption).foregroundStyle(.secondary)
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
                        Text(reachable ? (cable ? "erreichbar · per Kabel" : "erreichbar · WLAN") : "nicht gefunden")
                            .font(.caption).foregroundStyle(.secondary)
                            .contentTransition(.opacity)
                    }
                }
                Spacer()
                if reachable {
                    Text("Verbinden")
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
                Text("Mit \(host.name) koppeln").font(.title2.weight(.semibold))
                Text("Gib den 12-stelligen Code ein, den Tafel Host auf dem Mac zeigt.")
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
                Button("Abbrechen") { dismiss() }
                    .buttonStyle(.bordered)
                Button(action: submit) {
                    HStack(spacing: 8) {
                        if model.pairingBusy { ProgressView().tint(Brand.slateDeep) }
                        Text("Koppeln").fontWeight(.semibold)
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
        .presentationBackground(Brand.background)
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
