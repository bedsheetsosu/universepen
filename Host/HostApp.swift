import SwiftUI
import TafelKit

@main
struct TafelHostApp: App {
    @StateObject private var host = HostController()

    var body: some Scene {
        WindowGroup("Tafel") {
            HostView()
                .environmentObject(host)
                .frame(minWidth: 440, idealWidth: 480, minHeight: 560)
        }
        .windowResizability(.contentSize)

        Window("Stifttest", id: "pentest") {
            PenTestView()
        }
    }
}

struct HostView: View {
    @EnvironmentObject var host: HostController
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Form {
            statusSection
            permissionSection
            pairingSection
            sourceSection
            streamSection
        }
        .formStyle(.grouped)
        .task { await host.refreshSources() }
    }

    private var statusSection: some View {
        Section {
            HStack(spacing: 10) {
                Circle()
                    .fill(host.sessionDevice != nil ? Color.green : Color.secondary.opacity(0.4))
                    .frame(width: 10, height: 10)
                VStack(alignment: .leading, spacing: 2) {
                    Text(host.sessionDevice.map { "Verbunden mit \($0)" } ?? "Warte auf iPad")
                        .font(.headline)
                    if host.sessionDevice != nil, !host.sessionLink.isEmpty {
                        Text("Über \(host.sessionLink)").font(.caption).foregroundStyle(.secondary)
                    }
                    Text(host.listenerStatus).font(.caption).foregroundStyle(.secondary)
                }
            }
            if host.sessionDevice != nil, !host.clientDiagnostics.isEmpty {
                Text("iPad sieht: \(host.clientDiagnostics)").font(.caption2.monospaced()).foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            if let e = host.lastError {
                Text(e).font(.caption).foregroundStyle(.red)
            }
        }
    }

    private var permissionSection: some View {
        Section("Berechtigungen") {
            permissionRow("Bildschirmaufnahme", granted: host.screenRecordingGranted,
                          detail: "Für die Übertragung des Bildes.", action: host.requestScreenRecording)
            permissionRow("Bedienungshilfen", granted: host.accessibilityGranted,
                          detail: "Für Stift-, Scroll- und Tastatureingaben.", action: host.requestAccessibility)
        }
    }

    private func permissionRow(_ title: String, granted: Bool, detail: String, action: @escaping () -> Void) -> some View {
        HStack {
            Image(systemName: granted ? "checkmark.circle.fill" : "exclamationmark.circle")
                .foregroundStyle(granted ? .green : .orange)
            VStack(alignment: .leading) {
                Text(title)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if !granted { Button("Erlauben …", action: action) }
        }
    }

    private var pairingSection: some View {
        Section("Kopplung") {
            if let code = host.pairingCode {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Auf dem iPad eingeben:").font(.caption).foregroundStyle(.secondary)
                    Text(PairingCode.formatted(code))
                        .font(.system(size: 30, weight: .semibold, design: .monospaced))
                        .textSelection(.enabled)
                    Text("Gültig noch \(host.pairingSecondsLeft) s").font(.caption).foregroundStyle(.secondary)
                }
                Button("Abbrechen", role: .cancel) { host.endPairing() }
            } else {
                Button("iPad koppeln …") { host.beginPairing() }
                if let p = host.lastPaired {
                    Text("Gekoppelt: \(p)").font(.caption).foregroundStyle(.secondary)
                }
            }
            HStack {
                Text("Schlüssel-Fingerabdruck").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text(host.keyFingerprint).font(.caption.monospaced())
            }
            Toggle("Peer-to-Peer-WLAN (ohne Router)", isOn: $host.peerToPeer)
            Text("Nur einschalten, wenn Mac und iPad weder ein gemeinsames WLAN noch ein Kabel haben. Peer-to-Peer-WLAN erhöht die Latenz im normalen WLAN.")
                .font(.caption).foregroundStyle(.secondary)
            Button("Alle Kopplungen aufheben", role: .destructive) { host.unpairAll() }
                .font(.caption)
        }
    }

    private var sourceSection: some View {
        Section("Quelle") {
            Picker("Modus", selection: $host.mode) {
                ForEach(CaptureMode.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            Text(host.mode.help).font(.caption).foregroundStyle(.secondary)

            if host.mode == .window {
                Picker("Fenster", selection: $host.selectedWindow) {
                    ForEach(host.windows) { Text($0.title).lineLimit(1).tag($0.id) }
                }
            } else {
                Picker("Bildschirm", selection: $host.selectedDisplay) {
                    ForEach(host.displays) { Text($0.title).tag($0.id) }
                }
            }
            if host.mode == .region {
                LabeledContent("Größe") {
                    Slider(value: $host.regionZoom, in: 0.4...1)
                }
                LabeledContent("Horizontal") {
                    Slider(value: $host.regionAnchorX, in: 0...1)
                }
                LabeledContent("Vertikal") {
                    Slider(value: $host.regionAnchorY, in: 0...1)
                }
            }
            Button("Quellen aktualisieren") { Task { await host.refreshSources() } }
                .font(.caption)
        }
    }

    private var streamSection: some View {
        Section("Stream") {
            LabeledContent("Encoder", value: host.streamDescription.isEmpty ? "–" : host.streamDescription)
            LabeledContent("Bilder/s", value: String(format: "%.0f", host.stats.fps))
            LabeledContent("Datenrate", value: String(format: "%.1f Mbit/s", host.stats.mbps))
            LabeledContent("Verworfen (Netz-Stau)", value: "\(host.stats.dropped)")
            Button("Stifttest öffnen …") {
                openWindow(id: "pentest")
                Task { try? await Task.sleep(nanoseconds: 500_000_000); await host.refreshSources(); host.restartStream() }
            }
            Text("Zeigt, welche Druck-, Neigungs- und Rotationswerte eine Mac-App wirklich empfängt. Das Stifttest-Fenster wird mit übertragen, das Hauptfenster nicht.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}
