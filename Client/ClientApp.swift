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

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if model.phase.showsCanvas {
                CanvasRepresentable(model: model)
                    .ignoresSafeArea()
                overlay
                if case .reconnecting = model.phase {
                    VStack {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("Verbindung unterbrochen – verbinde neu …")
                        }
                        .font(.callout)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(.top, 12)
                        Spacer()
                    }
                    .allowsHitTesting(false)
                }
            } else {
                ConnectView()
            }
        }
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
            }
            VStack {
                HStack(alignment: .top) {
                    Spacer()
                    if showStatus || model.showStatusOverlay {
                        StatusPill()
                    }
                    Menu {
                        Button("Status \(showStatus ? "ausblenden" : "anzeigen")") { showStatus.toggle() }
                        Button(model.showKeyboard ? "Bildschirmtastatur ausblenden" : "Bildschirmtastatur") { model.showKeyboard.toggle() }
                        Button("Einstellungen …") { showSettings = true }
                        Button("Trennen", role: .destructive) { model.disconnect() }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 15, weight: .semibold))
                            .frame(width: 34, height: 34)
                            .background(.ultraThinMaterial, in: Circle())
                            .opacity(0.55)
                    }
                }
                Spacer()
            }
            .padding(10)
        }
    }
}

struct StatusPill: View {
    @EnvironmentObject var model: ClientModel

    var body: some View {
        HStack(spacing: 10) {
            Circle().fill(.green).frame(width: 7, height: 7)
            if let t = model.timing {
                Image(systemName: t.link.hasPrefix("USB") ? "cable.connector" : "wifi")
                Text("RTT \(Int(t.rttMs.rounded())) ms")
                if let age = t.frameAgeMs { Text("Bild \(Int(age.rounded())) ms") }
                Text("\(Int(t.fps)) fps")
            } else {
                Text("misst …")
            }
        }
        .font(.caption.monospacedDigit())
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: Capsule())
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
                        .font(.caption2.weight(.medium))
                        .lineLimit(1)
                        .frame(width: 58, height: 34)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }
        }
        .opacity(0.8)
    }
}

struct ConnectView: View {
    @EnvironmentObject var model: ClientModel
    @State private var pairTarget: DiscoveredHost?
    @State private var code = ""

    var body: some View {
        NavigationStack {
            List {
                statusSection
                Section("Gekoppelte Macs") {
                    let reachable = model.discovered.filter { model.isPaired($0) }
                    if model.paired.isEmpty {
                        Text("Noch kein Mac gekoppelt.").foregroundStyle(.secondary)
                    }
                    ForEach(model.paired) { p in
                        let host = reachable.first { $0.hostID == p.id }
                        HStack {
                            VStack(alignment: .leading) {
                                Text(p.name)
                                Text(host == nil ? "nicht gefunden" : "erreichbar")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if let host { Button("Verbinden") { model.connect(host) }.buttonStyle(.borderedProminent) }
                        }
                        .swipeActions { Button("Entfernen", role: .destructive) { model.forget(p) } }
                    }
                }
                Section {
                    if model.pairable.isEmpty {
                        Text("Am Mac in Tafel Host „iPad koppeln …“ wählen.").foregroundStyle(.secondary)
                    }
                    ForEach(model.pairable) { h in
                        Button { pairTarget = h; code = "" } label: {
                            Label("\(h.name) koppeln", systemImage: "link")
                        }
                    }
                } header: {
                    Text("Neu koppeln")
                } footer: {
                    Text("Nur Geräte mit dem einmaligen Code vom Mac werden gekoppelt. Verbindungen laufen verschlüsselt und direkt im lokalen Netz, ohne Server, Konto oder Cloud.")
                }
            }
            .navigationTitle("Tafel")
            .alert("Code vom Mac eingeben", isPresented: Binding(get: { pairTarget != nil }, set: { if !$0 { pairTarget = nil } })) {
                TextField("XXXX-XXXX-XXXX", text: $code)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                Button("Koppeln") { if let h = pairTarget { model.pair(with: h, code: code) } }
                Button("Abbrechen", role: .cancel) {}
            } message: {
                Text(pairTarget?.name ?? "")
            }
        }
    }

    @ViewBuilder private var statusSection: some View {
        switch model.phase {
        case .connecting(let name):
            Section { HStack { ProgressView(); Text("Verbinde mit \(name) …") } }
        case .failed(let msg):
            Section {
                Text(msg).foregroundStyle(.orange)
                Button("Erneut versuchen") { model.retry() }
            }
        default:
            EmptyView()
        }
        if model.pairingBusy {
            Section { HStack { ProgressView(); Text("Kopple …") } }
        }
        if let e = model.pairingError {
            Section { Text(e).foregroundStyle(.orange) }
        }
    }
}
