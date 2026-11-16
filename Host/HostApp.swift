import SwiftUI
import TafelKit

@main
struct TafelHostApp: App {
    // @State, not @StateObject: the App itself must not re-run on every change of the controller
    // (that redraws the menu bar icon on every display each time); the views observe it themselves.
    @State private var host = HostController()

    init() { Self.migrateOldDefaults() }

    /// The app was called "Tafel Host" (bundle ID local.tafel.host). Take its settings over once,
    /// before anything reads them, so mode, developer API switch etc. survive the rename.
    /// Pairing keys live in the keychain (service "Tafel") and are not affected by the bundle ID;
    /// macOS may ask once whether the renamed app may read them.
    private static func migrateOldDefaults() {
        let d = UserDefaults.standard
        guard !d.bool(forKey: "migratedFromTafelHost"), let id = Bundle.main.bundleIdentifier, id != "local.tafel.host" else { return }
        if let old = d.persistentDomain(forName: "local.tafel.host"), !old.isEmpty {
            var merged = old
            for (k, v) in d.persistentDomain(forName: id) ?? [:] { merged[k] = v }   // never overwrite newer values
            d.setPersistentDomain(merged, forName: id)
        }
        d.set(true, forKey: "migratedFromTafelHost")
    }

    var body: some Scene {
        WindowGroup("UniversePen", id: "main") {
            HostView()
                .environmentObject(host)
                .onOpenURL { host.handle(url: $0) }
                .frame(minWidth: 460, idealWidth: 500, minHeight: 600, idealHeight: 760)
                .preferredColorScheme(.dark)
        }
        .windowResizability(.contentMinSize)
        .windowToolbarStyle(.unifiedCompact)

        Window(L("Stifttest"), id: "pentest") {
            PenTestView()
        }

        Window(L("Plugins"), id: "plugins") {
            PluginsWindow().environmentObject(host)
        }

        MenuBarExtra {
            HostMenu().environmentObject(host)
        } label: {
            MenuBarIcon(state: host.menuIcon)
        }
    }
}

private struct MenuStatsLine: View {
    @ObservedObject var live: LiveStats
    var body: some View {
        if live.stats.fps > 0 {
            Text(String(format: "%.0f fps · %.1f Mbit/s", live.stats.fps, live.stats.mbps))
        }
    }
}

private struct StatTiles: View {
    @ObservedObject var live: LiveStats
    var body: some View {
        let s = live.stats
        HStack(spacing: 10) {
            StatTile(value: s.fps, format: "%.0f", unit: L("Bilder/s"), symbol: "film")
            StatTile(value: s.mbps, format: "%.1f",
                     unit: s.targetMbps > 0 ? L("Mbit/s · Ziel %.0f", s.targetMbps) : "Mbit/s",
                     symbol: "arrow.up.right")
            StatTile(value: Double(s.dropped), format: "%.0f", unit: L("verworfen"), symbol: "tray.and.arrow.down")
        }
    }
}

private struct MenuBarIcon: View {
    @ObservedObject var state: MenuIconState
    var body: some View {
        Image(systemName: state.lowBattery ? "battery.0percent" : state.connected ? "pencil.tip.crop.circle.fill" : "pencil.tip")
            .accessibilityLabel(state.connected ? L("UniversePen – verbunden") : "UniversePen")
    }
}

/// Menu bar menu: connection at a glance, mode switch, pairing.
struct HostMenu: View {
    @EnvironmentObject var host: HostController
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        if let device = host.sessionDevice {
            Text(L("Verbunden: %@", device))
            Text(localizedLink(host.sessionLink))
            ForEach(host.extraTablets, id: \.self) { t in Text(L("+ als Tablett: %@", t)) }
            MenuStatsLine(live: host.live)
            Button(L("Vorderstes Fenster aufs iPad")) { host.moveFrontWindowToIPad() }
                .keyboardShortcut("i", modifiers: [.control, .option, .command])
            if host.heatLevel > 0, host.heatGuard { Text(L("Mac ist heiß – Stream gedrosselt (30 fps).")) }
            if let b = host.ipadBattery {
                Text(L("iPad-Akku: %d %%", Int((b * 100).rounded())) + (host.ipadCharging == true ? " ⚡︎" : ""))
            }
        } else {
            Text(host.listenerReady ? L("Warte auf das iPad …") : host.listenerStatus)
        }
        Divider()
        Picker(L("Quelle"), selection: $host.mode) {
            ForEach(CaptureMode.allCases) { m in
                Text(m.title).tag(m)
                    .disabled(m == .virtual && !HostController.secondScreenAvailable)
            }
        }
        Button(L("iPad koppeln …")) {
            openMain()
            host.beginPairing()
        }
        Button(host.paletteArea == nil ? L("Palette fürs iPad wählen …") : L("Palette neu wählen …")) { host.pickPalette() }
        if host.paletteArea != nil { Button(L("Palette entfernen")) { host.removePalette() } }
        Toggle(L("Hitzeschutz"), isOn: $host.heatGuard)
        Divider()
        if host.timelapseRunning {
            Button(L("Zeitraffer stoppen")) { host.stopTimelapse() }
        } else {
            Button(L("Zeitraffer aufnehmen")) { host.startTimelapse() }
        }
        Button(L("Plugins …")) {
            openWindow(id: "plugins")
            NSApp.activate()
        }
        Divider()
        Button(L("UniversePen öffnen")) { openMain() }
        Button(L("UniversePen beenden")) { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }

    private func openMain() {
        openWindow(id: "main")
        NSApp.activate()
    }
}


struct HostView: View {
    /// Redraw when the colours change.
    @ObservedObject var theme = Theme.shared
    @EnvironmentObject var host: HostController
    @Environment(\.openWindow) private var openWindow
    @State private var confirmUnpair = false
    @AppStorage("hostOnboardingDone") private var onboardingDone = false
    @ObservedObject private var l10n = L10n.shared

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
                developer
                pluginsCard
                VStack(alignment: .leading, spacing: 10) {
                    SectionTitle(L("Farben"), symbol: "paintpalette")
                    ThemeChoice()
                }
                .tafelCard()
                LanguageChoice().frame(maxWidth: 520)
                Button {
                    onboardingDone = false
                } label: {
                    Label(L("Einrichtung erneut starten"), systemImage: "sparkles")
                }
                .buttonStyle(.borderless)
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding(18)
        }
        .scrollContentBackground(.hidden)
        .background(ThemeBackground().ignoresSafeArea())
        .animation(Brand.spring, value: connected)
        .animation(Brand.spring, value: allGranted)
        .animation(Brand.spring, value: host.pairingCode)
        .animation(Brand.spring, value: host.mode)
        .id(l10n.language)   // re-render every text when the language changes
        .task { await host.refreshSources() }
        .sheet(isPresented: Binding(get: { !onboardingDone }, set: { if !$0 { onboardingDone = true } })) {
            HostOnboarding(done: $onboardingDone).environmentObject(host)
        }
    }

    // MARK: Hero: connection state

    private var hero: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 16) {
                ConnectionOrb(connected: connected, usb: host.sessionLink.hasPrefix("USB"))
                    .frame(width: 64, height: 64)
                VStack(alignment: .leading, spacing: 5) {
                    Text(host.sessionDevice ?? L("Warte auf iPad …"))
                        .font(.title2.weight(.semibold))
                        .contentTransition(.opacity)
                    if connected {
                        LinkBadge(link: host.sessionLink)
                            .transition(.scale(scale: 0.8, anchor: .leading).combined(with: .opacity))
                    } else {
                        Text(L("UniversePen auf dem iPad öffnen – es verbindet sich automatisch."))
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    if !host.extraTablets.isEmpty {
                        Label(L("+ als Tablett: %@", host.extraTablets.joined(separator: ", ")), systemImage: "rectangle.dashed")
                            .font(.callout).foregroundStyle(Brand.mint)
                    }
                }
                Spacer(minLength: 0)
            }
            if connected {
                StatTiles(live: host.live)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            HStack(spacing: 6) {
                Circle().fill(host.listenerReady ? Brand.mint : .orange).frame(width: 6, height: 6)
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
            SectionTitle(L("Berechtigungen"), symbol: "lock.shield")
            permissionRow(L("Bildschirmaufnahme"), detail: L("Für die Übertragung des Bildes."),
                          granted: host.screenRecordingGranted, action: host.requestScreenRecording)
            permissionRow(L("Bedienungshilfen"), detail: L("Für Stift, Maus, Scrollen und Tastatur."),
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
                Button(L("Erlauben …"), action: action).buttonStyle(.borderedProminent).tint(Brand.mint.opacity(0.85))
            }
        }
    }

    // MARK: Pairing

    private var pairing: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle(L("Kopplung"), symbol: "link")
            if let code = host.pairingCode {
                HStack(spacing: 18) {
                    CountdownRing(fraction: Double(host.pairingSecondsLeft) / 120, seconds: host.pairingSecondsLeft)
                        .frame(width: 54, height: 54)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L("Auf dem iPad eingeben")).font(.caption).foregroundStyle(.secondary)
                        Text(PairingCode.formatted(code))
                            .font(.system(size: 32, weight: .semibold, design: .monospaced))
                            .kerning(2)
                            .textSelection(.enabled)
                            .foregroundStyle(LinearGradient(colors: [.white, Brand.mintBright], startPoint: .leading, endPoint: .trailing))
                    }
                    Spacer()
                    Button(L("Abbrechen"), role: .cancel) { host.endPairing() }
                }
                .transition(.scale(scale: 0.95).combined(with: .opacity))
            } else {
                HStack {
                    Button {
                        host.beginPairing()
                    } label: {
                        Label(L("iPad koppeln …"), systemImage: "ipad.and.arrow.forward")
                            .padding(.horizontal, 6).padding(.vertical, 2)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Brand.mint.opacity(0.85))
                    .controlSize(.large)
                    Spacer()
                    if let p = host.lastPaired {
                        Label(L("Gekoppelt: %@", p), systemImage: "checkmark.seal.fill")
                            .font(.caption).foregroundStyle(Brand.mint)
                            .transition(.opacity)
                    }
                }
            }
            Divider().opacity(0.4)
            Toggle(isOn: $host.peerToPeer) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("Peer-to-Peer-WLAN (ohne Router)"))
                    Text(L("Nur ohne gemeinsames WLAN und ohne Kabel einschalten – kostet Latenz."))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.switch)
            HStack {
                Text(L("Schlüssel-Fingerabdruck")).font(.caption).foregroundStyle(.secondary)
                Text(host.keyFingerprint).font(.caption.monospaced()).foregroundStyle(.secondary)
                Spacer()
                Button(L("Alle Kopplungen aufheben …"), role: .destructive) { confirmUnpair = true }
                    .font(.caption)
                    .buttonStyle(.borderless)
            }
        }
        .tafelCard()
        .confirmationDialog(L("Alle Kopplungen aufheben?"), isPresented: $confirmUnpair) {
            Button(L("Aufheben"), role: .destructive) { host.unpairAll() }
        } message: {
            Text(L("Jedes iPad muss danach neu gekoppelt werden."))
        }
    }

    // MARK: Source

    private var source: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle(L("Quelle"), symbol: "rectangle.dashed.badge.record")
            HStack(spacing: 8) {
                ForEach(CaptureMode.allCases) { m in
                    let unavailable = m == .virtual && !HostController.secondScreenAvailable
                    ModeButton(mode: m, selected: host.mode == m) { host.mode = m }
                        .disabled(unavailable)
                        .opacity(unavailable ? 0.4 : 1)
                        .help(unavailable ? L("Auf diesem macOS nicht verfügbar: die private Schnittstelle hat sich geändert.") : m.title)
                }
            }
            Text(host.mode.help).font(.caption).foregroundStyle(.secondary)
            HStack {
                Button {
                    host.pickPalette()
                } label: {
                    Label(host.paletteArea == nil ? L("Palette fürs iPad wählen …") : L("Palette neu wählen …"), systemImage: "square.on.square.dashed")
                }
                if host.paletteArea != nil {
                    Button(L("Palette entfernen"), role: .destructive) { host.removePalette() }
                }
                Spacer()
            }
            Text(L("Ein Bereich des Macs (z. B. Ebenen- oder Farbpalette) schwebt live als kleines Fenster auf dem iPad und lässt sich dort antippen."))
                .font(.caption).foregroundStyle(.secondary)
            Picker(L("Laserpointer-Farbe"), selection: $host.laserColour) {
                ForEach(LaserOverlay.Colour.allCases) { c in
                    Label { Text(c.title) } icon: { Image(systemName: "circle.fill").foregroundStyle(Color(nsColor: c.color)) }.tag(c)
                }
            }
            Text(L("Tastenkürzel: ⌃⌥⌘T Tablett-Modus · ⌃⌥⌘P Palette wählen · ⌃⌥⌘I vorderstes Fenster aufs iPad"))
                .font(.caption).foregroundStyle(.secondary)
                .contentTransition(.opacity)
            if !HostController.secondScreenAvailable {
                Label(L("„Zweiter Bildschirm“ ist auf diesem macOS nicht verfügbar – die private Schnittstelle hat sich geändert. Details stehen im Log (Konsole, Prozess „UniversePen Host“)."),
                      systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.orange)
            }

            if host.mode == .window {
                Picker(L("Fenster"), selection: $host.selectedWindow) {
                    ForEach(host.windows) { Text($0.title).lineLimit(1).tag($0.id) }
                }
                .transition(.opacity)
            } else if host.mode != .virtual {
                Picker(L("Bildschirm"), selection: $host.selectedDisplay) {
                    ForEach(host.displays) { Text($0.title).tag($0.id) }
                }
            }
            if host.mode == .virtual {
                Label(L("Experimentell · private macOS-Schnittstelle"), systemImage: "flask")
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 9).padding(.vertical, 4)
                    .background(Color.orange.opacity(0.18), in: Capsule())
                    .foregroundStyle(.orange)
                    .transition(.opacity)
            }
            if host.mode == .region {
                VStack(spacing: 8) {
                    sliderRow(L("Größe"), value: $host.regionZoom, range: 0.2...1, symbol: "arrow.up.left.and.arrow.down.right")
                    Toggle(isOn: $host.regionFollow) {
                        Label(L("Lupe folgt dem Stift"), systemImage: "plus.magnifyingglass")
                    }
                    .help(L("Der Ausschnitt wandert mit, wenn der Stift an den Rand des iPads kommt, und springt zum Zeiger, wenn du ihn am Mac woanders hinbewegst."))
                    sliderRow(L("Horizontal"), value: $host.regionAnchorX, range: 0...1, symbol: "arrow.left.and.right")
                    sliderRow(L("Vertikal"), value: $host.regionAnchorY, range: 0...1, symbol: "arrow.up.and.down")
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }
            Button {
                Task { await host.refreshSources() }
            } label: {
                Label(L("Quellen aktualisieren"), systemImage: "arrow.clockwise")
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

    // MARK: Developer API

    private var developer: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(L("Entwickler"), symbol: "chevron.left.forwardslash.chevron.right")
            Toggle(isOn: $host.devAPIEnabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("Entwickler-API"))
                    Text(L("Andere Programme auf diesem Mac lesen Stift-Eingaben und steuern UniversePen (nur lokal, 127.0.0.1:%d).", Int(DeveloperAPI.defaultPort)))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.switch)
            if host.devAPIEnabled {
                Label(L("%d Programme verbunden", host.devAPIClients), systemImage: "link")
                    .font(.caption).foregroundStyle(host.devAPIClients > 0 ? Brand.mint : .secondary)
                    .contentTransition(.numericText())
            }
            if let e = host.devAPIError { Text(e).font(.caption).foregroundStyle(.orange) }
            Link(L("Dokumentation (SDK, MIT-Lizenz)"), destination: URL(string: "https://github.com/bedsheetsosu/universepen/tree/main/SDK")!)
                .font(.caption)
        }
        .tafelCard()
        .animation(Brand.spring, value: host.devAPIEnabled)
    }

    // MARK: Stream

    /// The iPad sends its diagnostics with fixed German labels; show them in the Mac's language.
    static func localizedDiagnostics(_ s: String) -> String {
        var r = localizedLink(s)
        guard L10n.shared.language != .de else { return r }
        for (de, shown) in [("sichtbar:", L("sichtbar:")), ("Kabel-Kandidat:", L("Kabel-Kandidat:")),
                            ("Weg:", L("Weg:")), ("keiner", L("keiner"))] {
            r = r.replacingOccurrences(of: de, with: shown)
        }
        return r
    }

    private var pluginsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(L("Plugins"), symbol: "puzzlepiece.extension")
            Text(L("Eigene Erweiterungen in JavaScript: Stift-Filter (z. B. Glättung), Gesten-Makros, Aktionen für das iPad, Einstellungen steuern. Wie OpenTabletDriver-Plugins, nur für UniversePen."))
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Button { openWindow(id: "plugins") } label: { Label(L("Plugins …"), systemImage: "puzzlepiece.extension") }
                let on = host.plugins.entries.filter(\.enabled).count
                if on > 0 { Text(L("%d aktiv", on)).font(.caption).foregroundStyle(Brand.mint) }
                Spacer()
                Link(L("Plugin-Doku"), destination: URL(string: "https://github.com/bedsheetsosu/universepen/tree/main/SDK/plugins")!)
                    .font(.caption)
            }
        }
        .tafelCard()
    }

    private var stream: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle("Stream", symbol: "waveform.path.ecg")
            LabeledContent(L("Encoder")) {
                Text(host.streamDescription.isEmpty ? "–" : host.streamDescription)
                    .font(.caption.monospaced()).multilineTextAlignment(.trailing)
            }
            HStack {
                Button {
                    openWindow(id: "pentest")
                    Task { try? await Task.sleep(nanoseconds: 500_000_000); await host.refreshSources(); host.restartStream() }
                } label: {
                    Label(L("Stifttest öffnen …"), systemImage: "applepencil.and.scribble")
                }
                Spacer()
            }
            Text(L("Zeigt, welche Druck-, Neigungs- und Rotationswerte eine Mac-App wirklich empfängt."))
                .font(.caption).foregroundStyle(.secondary)
            Toggle(L("Beim Anmelden öffnen"), isOn: Binding(get: { host.openAtLogin }, set: { host.setOpenAtLogin($0) }))
            Toggle(isOn: $host.heatGuard) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("Hitzeschutz"))
                    Text(host.heatLevel == 0 ? L("Wird der Mac heiß, sinken Bildrate und Bitrate, bis er wieder kühl ist.")
                         : host.heatGuard ? L("Mac ist heiß – Stream gedrosselt (30 fps).")
                         : L("Mac ist heiß."))
                        .font(.caption).foregroundStyle(host.heatLevel > 0 ? .orange : .secondary)
                }
            }
            Divider().opacity(0.4)
            TimelapseControls()
            if !host.clientDiagnostics.isEmpty, connected {
                DisclosureGroup(L("Netzwerk-Diagnose")) {
                    Text(Self.localizedDiagnostics(host.clientDiagnostics)).font(.caption2.monospaced()).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .font(.caption)
            }
        }
        .tafelCard()
    }
}

// MARK: - Components

/// Start/stop the time-lapse, speed, running time and the last file.
private struct TimelapseControls: View {
    @EnvironmentObject var host: HostController
    @ObservedObject var theme = Theme.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Button {
                    withAnimation(Brand.spring) { host.timelapseRunning ? host.stopTimelapse() : host.startTimelapse() }
                } label: {
                    Label(host.timelapseRunning ? L("Zeitraffer stoppen") : L("Zeitraffer aufnehmen"),
                          systemImage: host.timelapseRunning ? "stop.circle.fill" : "record.circle")
                }
                .tint(host.timelapseRunning ? .red : Brand.mint)
                Spacer()
                Text(L("Tempo"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize()
                Picker(L("Tempo"), selection: $host.timelapseSpeed) {
                    Text("10×").tag(10)
                    Text("30×").tag(30)
                    Text("60×").tag(60)
                    Text("120×").tag(120)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .disabled(host.timelapseRunning)
            }
            if host.timelapseRunning, let start = host.timelapseStarted {
                TimelineView(.periodic(from: start, by: 1)) { ctx in
                    let secs = Int(ctx.date.timeIntervalSince(start))
                    let movie = Double(host.timelapseFrames) / Double(TimelapseRecorder.outputFPS)
                    Text(L("Läuft seit %@ · %lld Bilder · ergibt %@ Video", Self.clock(secs), host.timelapseFrames, Self.clock(Int(movie.rounded()))))
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
            } else if let file = host.timelapseLastFile {
                HStack {
                    Text(file.lastPathComponent).font(.caption).lineLimit(1).truncationMode(.middle)
                    Button(L("Im Finder zeigen")) { NSWorkspace.shared.activateFileViewerSelecting([file]) }
                        .buttonStyle(.link).font(.caption)
                }
            }
            Text(L("Nimmt das übertragene Bild als Zeitraffer auf (Filme → UniversePen). Ruhephasen ohne Bildänderung werden automatisch übersprungen."))
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    static func clock(_ s: Int) -> String { String(format: "%d:%02d", s / 60, s % 60) }
}

private struct SectionTitle: View {
    /// Redraw when the colours change.
    @ObservedObject var theme = Theme.shared
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
    /// Redraw when the colours change.
    @ObservedObject var theme = Theme.shared
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
    /// Redraw when the colours change.
    @ObservedObject var theme = Theme.shared
    let link: String
    var body: some View {
        let usb = link.hasPrefix("USB")
        Label(link.isEmpty ? L("verbunden") : localizedLink(link), systemImage: usb ? "cable.connector" : "wifi")
            .font(.caption.weight(.medium))
            .padding(.horizontal, 9).padding(.vertical, 4)
            .background((usb ? Brand.mint : Color.orange).opacity(0.18), in: Capsule())
            .foregroundStyle(usb ? Brand.mintBright : .orange)
    }
}

private struct StatTile: View {
    /// Redraw when the colours change.
    @ObservedObject var theme = Theme.shared
    let value: Double
    let format: String
    let unit: String
    let symbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: symbol).font(.caption).foregroundStyle(Brand.mint)
            Text(String(format: format, value))
                .font(.system(.title3, design: .rounded).weight(.semibold).monospacedDigit())
                // No rolling-digit animation: it changes every second and is drawn on the CPU.
            Text(unit).font(.caption2).foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

struct CountdownRing: View {
    /// Redraw when the colours change.
    @ObservedObject var theme = Theme.shared
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

struct ModeButton: View {
    /// Redraw when the colours change.
    @ObservedObject var theme = Theme.shared
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
