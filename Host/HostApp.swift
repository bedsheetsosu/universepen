import SwiftUI
import TafelKit

@main
struct TafelHostApp: App {
    @StateObject private var host = HostController()

    var body: some Scene {
        WindowGroup("Tafel") {
            HostView()
                .environmentObject(host)
                .frame(minWidth: 460, idealWidth: 500, minHeight: 600, idealHeight: 760)
                .preferredColorScheme(.dark)
        }
        .windowResizability(.contentMinSize)
        .windowToolbarStyle(.unifiedCompact)

        Window("Stifttest", id: "pentest") {
            PenTestView()
        }
    }
}

struct HostView: View {
    @EnvironmentObject var host: HostController
    @Environment(\.openWindow) private var openWindow
    @State private var confirmUnpair = false

    private var connected: Bool { host.sessionDevice != nil }
    private var allGranted: Bool { host.screenRecordingGranted && host.accessibilityGranted }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                hero
                if !allGranted {
                    permissions.transition(.move(edge: .top).combined(with: .opacity))
                }
                pairing
                source
                stream
            }
            .padding(18)
        }
        .scrollContentBackground(.hidden)
        .background(Brand.background.ignoresSafeArea())
        .animation(Brand.spring, value: connected)
        .animation(Brand.spring, value: allGranted)
        .animation(Brand.spring, value: host.pairingCode)
        .animation(Brand.spring, value: host.mode)
        .task { await host.refreshSources() }
    }

    // MARK: Hero: connection state

    private var hero: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 16) {
                ConnectionOrb(connected: connected, usb: host.sessionLink.hasPrefix("USB"))
                    .frame(width: 64, height: 64)
                VStack(alignment: .leading, spacing: 5) {
                    Text(host.sessionDevice ?? "Warte auf iPad …")
                        .font(.title2.weight(.semibold))
                        .contentTransition(.opacity)
                    if connected {
                        LinkBadge(link: host.sessionLink)
                            .transition(.scale(scale: 0.8, anchor: .leading).combined(with: .opacity))
                    } else {
                        Text("Tafel auf dem iPad öffnen – es verbindet sich automatisch.")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
            if connected {
                HStack(spacing: 10) {
                    StatTile(value: host.stats.fps, format: "%.0f", unit: "Bilder/s", symbol: "film")
                    StatTile(value: host.stats.mbps, format: "%.1f", unit: "Mbit/s", symbol: "arrow.up.right")
                    StatTile(value: Double(host.stats.dropped), format: "%.0f", unit: "verworfen", symbol: "tray.and.arrow.down")
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            HStack(spacing: 6) {
                Circle().fill(host.listenerStatus.hasPrefix("Bereit") ? Brand.mint : .orange).frame(width: 6, height: 6)
                Text(host.listenerStatus).font(.caption).foregroundStyle(.secondary)
            }
            if let e = host.lastError {
                Label(e, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundStyle(.orange)
                    .transition(.opacity)
            }
        }
        .tafelCard(padding: 20)
    }

    // MARK: Permissions (only while something is missing)

    private var permissions: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle("Berechtigungen", symbol: "lock.shield")
            permissionRow("Bildschirmaufnahme", detail: "Für die Übertragung des Bildes.",
                          granted: host.screenRecordingGranted, action: host.requestScreenRecording)
            permissionRow("Bedienungshilfen", detail: "Für Stift, Maus, Scrollen und Tastatur.",
                          granted: host.accessibilityGranted, action: host.requestAccessibility)
        }
        .tafelCard()
    }

    private func permissionRow(_ title: String, detail: String, granted: Bool, action: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            Image(systemName: granted ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .font(.title3)
                .foregroundStyle(granted ? Brand.mint : .orange)
                .contentTransition(.symbolEffect(.replace))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if !granted {
                Button("Erlauben …", action: action).buttonStyle(.borderedProminent).tint(Brand.mint.opacity(0.85))
            }
        }
    }

    // MARK: Pairing

    private var pairing: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle("Kopplung", symbol: "link")
            if let code = host.pairingCode {
                HStack(spacing: 18) {
                    CountdownRing(fraction: Double(host.pairingSecondsLeft) / 120, seconds: host.pairingSecondsLeft)
                        .frame(width: 54, height: 54)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Auf dem iPad eingeben").font(.caption).foregroundStyle(.secondary)
                        Text(PairingCode.formatted(code))
                            .font(.system(size: 32, weight: .semibold, design: .monospaced))
                            .kerning(2)
                            .textSelection(.enabled)
                            .foregroundStyle(LinearGradient(colors: [.white, Brand.mintBright], startPoint: .leading, endPoint: .trailing))
                    }
                    Spacer()
                    Button("Abbrechen", role: .cancel) { host.endPairing() }
                }
                .transition(.scale(scale: 0.95).combined(with: .opacity))
            } else {
                HStack {
                    Button {
                        host.beginPairing()
                    } label: {
                        Label("iPad koppeln …", systemImage: "ipad.and.arrow.forward")
                            .padding(.horizontal, 6).padding(.vertical, 2)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Brand.mint.opacity(0.85))
                    .controlSize(.large)
                    Spacer()
                    if let p = host.lastPaired {
                        Label("Gekoppelt: \(p)", systemImage: "checkmark.seal.fill")
                            .font(.caption).foregroundStyle(Brand.mint)
                            .transition(.opacity)
                    }
                }
            }
            Divider().opacity(0.4)
            Toggle(isOn: $host.peerToPeer) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Peer-to-Peer-WLAN (ohne Router)")
                    Text("Nur ohne gemeinsames WLAN und ohne Kabel einschalten – kostet Latenz.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.switch)
            HStack {
                Text("Schlüssel-Fingerabdruck").font(.caption).foregroundStyle(.secondary)
                Text(host.keyFingerprint).font(.caption.monospaced()).foregroundStyle(.secondary)
                Spacer()
                Button("Alle Kopplungen aufheben …", role: .destructive) { confirmUnpair = true }
                    .font(.caption)
                    .buttonStyle(.borderless)
            }
        }
        .tafelCard()
        .confirmationDialog("Alle Kopplungen aufheben?", isPresented: $confirmUnpair) {
            Button("Aufheben", role: .destructive) { host.unpairAll() }
        } message: {
            Text("Jedes iPad muss danach neu gekoppelt werden.")
        }
    }

    // MARK: Source

    private var source: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle("Quelle", symbol: "rectangle.dashed.badge.record")
            HStack(spacing: 8) {
                ForEach(CaptureMode.allCases) { m in
                    let unavailable = m == .virtual && !HostController.secondScreenAvailable
                    ModeButton(mode: m, selected: host.mode == m) { host.mode = m }
                        .disabled(unavailable)
                        .opacity(unavailable ? 0.4 : 1)
                        .help(unavailable ? "Auf diesem macOS nicht verfügbar: die private Schnittstelle hat sich geändert." : m.title)
                }
            }
            Text(host.mode.help).font(.caption).foregroundStyle(.secondary)
                .contentTransition(.opacity)
            if !HostController.secondScreenAvailable {
                Label("„Zweiter Bildschirm“ ist auf diesem macOS nicht verfügbar – die private Schnittstelle hat sich geändert. Details stehen im Log (Konsole, Prozess „Tafel Host“).",
                      systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.orange)
            }

            if host.mode == .window {
                Picker("Fenster", selection: $host.selectedWindow) {
                    ForEach(host.windows) { Text($0.title).lineLimit(1).tag($0.id) }
                }
                .transition(.opacity)
            } else if host.mode != .virtual {
                Picker("Bildschirm", selection: $host.selectedDisplay) {
                    ForEach(host.displays) { Text($0.title).tag($0.id) }
                }
            }
            if host.mode == .virtual {
                Label("Experimentell · private macOS-Schnittstelle", systemImage: "flask")
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 9).padding(.vertical, 4)
                    .background(Color.orange.opacity(0.18), in: Capsule())
                    .foregroundStyle(.orange)
                    .transition(.opacity)
            }
            if host.mode == .region {
                VStack(spacing: 8) {
                    sliderRow("Größe", value: $host.regionZoom, range: 0.4...1, symbol: "arrow.up.left.and.arrow.down.right")
                    sliderRow("Horizontal", value: $host.regionAnchorX, range: 0...1, symbol: "arrow.left.and.right")
                    sliderRow("Vertikal", value: $host.regionAnchorY, range: 0...1, symbol: "arrow.up.and.down")
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }
            Button {
                Task { await host.refreshSources() }
            } label: {
                Label("Quellen aktualisieren", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.borderless).font(.caption)
        }
        .tafelCard()
    }

    private func sliderRow(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, symbol: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).frame(width: 18).foregroundStyle(.secondary)
            Text(title).frame(width: 80, alignment: .leading)
            Slider(value: value, in: range).tint(Brand.mint)
        }
    }

    // MARK: Stream

    private var stream: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle("Stream", symbol: "waveform.path.ecg")
            LabeledContent("Encoder") {
                Text(host.streamDescription.isEmpty ? "–" : host.streamDescription)
                    .font(.caption.monospaced()).multilineTextAlignment(.trailing)
            }
            HStack {
                Button {
                    openWindow(id: "pentest")
                    Task { try? await Task.sleep(nanoseconds: 500_000_000); await host.refreshSources(); host.restartStream() }
                } label: {
                    Label("Stifttest öffnen …", systemImage: "applepencil.and.scribble")
                }
                Spacer()
            }
            Text("Zeigt, welche Druck-, Neigungs- und Rotationswerte eine Mac-App wirklich empfängt. Das Stifttest-Fenster wird mit übertragen, dieses Fenster nicht.")
                .font(.caption).foregroundStyle(.secondary)
            if !host.clientDiagnostics.isEmpty, connected {
                DisclosureGroup("Netzwerk-Diagnose") {
                    Text(host.clientDiagnostics).font(.caption2.monospaced()).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .font(.caption)
            }
        }
        .tafelCard()
    }
}

// MARK: - Components

private struct SectionTitle: View {
    let title: String
    let symbol: String
    init(_ title: String, symbol: String) { self.title = title; self.symbol = symbol }
    var body: some View {
        Label(title, systemImage: symbol)
            .font(.headline)
            .foregroundStyle(Brand.mintBright)
    }
}

/// Animated state light: pulsing rings while waiting, a glowing filled orb when connected.
private struct ConnectionOrb: View {
    let connected: Bool
    let usb: Bool

    var body: some View {
        ZStack {
            PulseRings(color: Brand.mint, active: !connected)
            Circle()
                .fill(connected
                      ? AnyShapeStyle(LinearGradient(colors: [Brand.mintBright, Brand.mint], startPoint: .top, endPoint: .bottom))
                      : AnyShapeStyle(Color.white.opacity(0.08)))
                .shadow(color: connected ? Brand.mint.opacity(0.7) : .clear, radius: 14)
            Image(systemName: connected ? (usb ? "cable.connector" : "wifi") : "ipad.landscape")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(connected ? Brand.slateDeep : .white.opacity(0.7))
                .contentTransition(.symbolEffect(.replace))
                .symbolEffect(.pulse, options: .repeating, isActive: !connected)
        }
    }
}

private struct LinkBadge: View {
    let link: String
    var body: some View {
        let usb = link.hasPrefix("USB")
        Label(link.isEmpty ? "verbunden" : link, systemImage: usb ? "cable.connector" : "wifi")
            .font(.caption.weight(.medium))
            .padding(.horizontal, 9).padding(.vertical, 4)
            .background((usb ? Brand.mint : Color.orange).opacity(0.18), in: Capsule())
            .foregroundStyle(usb ? Brand.mintBright : .orange)
    }
}

private struct StatTile: View {
    let value: Double
    let format: String
    let unit: String
    let symbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: symbol).font(.caption).foregroundStyle(Brand.mint)
            Text(String(format: format, value))
                .font(.system(.title3, design: .rounded).weight(.semibold).monospacedDigit())
                .contentTransition(.numericText(value: value))
                .animation(.snappy, value: value)
            Text(unit).font(.caption2).foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct CountdownRing: View {
    let fraction: Double
    let seconds: Int
    var body: some View {
        ZStack {
            Circle().stroke(.white.opacity(0.1), lineWidth: 5)
            Circle()
                .trim(from: 0, to: max(0, min(1, fraction)))
                .stroke(Brand.mint, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 1), value: fraction)
            Text("\(seconds)")
                .font(.system(.callout, design: .rounded).weight(.semibold).monospacedDigit())
                .contentTransition(.numericText(countsDown: true))
                .animation(.snappy, value: seconds)
        }
    }
}

private struct ModeButton: View {
    let mode: CaptureMode
    let selected: Bool
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: mode.symbol)
                    .font(.system(size: 20))
                    .symbolEffect(.bounce, value: selected)
                Text(mode.title).font(.caption.weight(.medium)).lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .foregroundStyle(selected ? Brand.slateDeep : .primary)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(selected ? AnyShapeStyle(Brand.mint) : AnyShapeStyle(Color.white.opacity(hover ? 0.1 : 0.05)))
            }
            .scaleEffect(hover && !selected ? 1.02 : 1)
        }
        .buttonStyle(.plain)
        .onHover { h in withAnimation(.easeOut(duration: 0.15)) { hover = h } }
        .animation(Brand.spring, value: selected)
    }
}
