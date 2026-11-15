import SwiftUI
import TafelKit

/// First-run setup on the Mac: permissions, default source, pairing.
struct HostOnboarding: View {
    @EnvironmentObject var host: HostController
    @ObservedObject private var l10n = L10n.shared
    @Binding var done: Bool
    @State private var step = 0
    @State private var forward = true
    @State private var pairedAtStart: String?

    private let steps = 5

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                page
                    .id(step)
                    .transition(.asymmetric(
                        insertion: .move(edge: forward ? .trailing : .leading).combined(with: .opacity),
                        removal: .move(edge: forward ? .leading : .trailing).combined(with: .opacity)))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(28)
            footer
        }
        .frame(width: 560, height: 560)
        .background(Brand.background)
        .preferredColorScheme(.dark)
        .animation(.spring(response: 0.5, dampingFraction: 0.86), value: step)
        .animation(Brand.spring, value: host.screenRecordingGranted && host.accessibilityGranted)
        .animation(Brand.spring, value: host.pairingCode)
        .animation(Brand.spring, value: host.lastPaired)
        .onAppear { pairedAtStart = host.lastPaired }
    }

    @ViewBuilder private var page: some View {
        switch step {
        case 0: language
        case 1: welcome
        case 2: permissions
        case 3: source
        default: pairing
        }
    }

    private var footer: some View {
        HStack {
            Button(L("Zurück")) { go(-1) }.opacity(step == 0 ? 0 : 1).disabled(step == 0)
            Spacer()
            HStack(spacing: 7) {
                ForEach(0..<steps, id: \.self) { i in
                    Capsule().fill(i == step ? Brand.mint : .white.opacity(0.2))
                        .frame(width: i == step ? 20 : 7, height: 7)
                }
            }
            Spacer()
            Button(step == steps - 1 ? L("Fertig") : L("Weiter")) {
                if step == steps - 1 { host.endPairing(); done = true } else { go(1) }
            }
            .buttonStyle(.borderedProminent)
            .tint(Brand.mint.opacity(0.9))
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 28)
        .padding(.bottom, 22)
    }

    private func go(_ d: Int) {
        forward = d > 0
        step = max(0, min(steps - 1, step + d))
    }

    // MARK: Pages

    private var language: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "globe").font(.system(size: 40, weight: .semibold)).foregroundStyle(Brand.mint)
            Text("Language · Sprache").font(.system(size: 28, weight: .bold, design: .rounded))
            Text("Choose your language. · Wähle deine Sprache.").foregroundStyle(.secondary)
            LanguageChoice().frame(maxWidth: 480)
            Spacer()
        }
    }

    private var welcome: some View {
        VStack(spacing: 18) {
            Spacer()
            ZStack {
                PulseRings(color: Brand.mint).frame(width: 120, height: 120)
                TafelMark().frame(width: 96, height: 96).shadow(color: Brand.mint.opacity(0.4), radius: 24)
            }
            Text(L("Willkommen bei Tafel")).font(.system(size: 30, weight: .bold, design: .rounded))
            Text(L("Tafel macht dein iPad zum Zeichendisplay für diesen Mac – per USB-Kabel oder WLAN, verschlüsselt und ohne Cloud. In drei Schritten ist alles eingerichtet."))
                .multilineTextAlignment(.center).foregroundStyle(.secondary)
                .frame(maxWidth: 420)
            Spacer()
        }
    }

    private var permissions: some View {
        VStack(alignment: .leading, spacing: 14) {
            header("lock.shield", L("Zwei Berechtigungen"),
                   L("macOS fragt einmal nach. Danach bleibt es so – auch nach Updates von Tafel."))
            permissionRow(L("Bildschirmaufnahme"), L("Damit das Bild aufs iPad kommt."), host.screenRecordingGranted, host.requestScreenRecording)
            permissionRow(L("Bedienungshilfen"), L("Damit Stift, Finger, Maus und Tastatur am Mac ankommen."), host.accessibilityGranted, host.requestAccessibility)
            if host.screenRecordingGranted && host.accessibilityGranted {
                Label(L("Alles erlaubt."), systemImage: "checkmark.seal.fill")
                    .foregroundStyle(Brand.mint).font(.headline)
                    .transition(.scale.combined(with: .opacity))
            } else {
                Text(L("Nach dem Erlauben in den Systemeinstellungen springt das Häkchen hier von selbst um. Bei der Bildschirmaufnahme kann macOS einen Neustart von Tafel Host verlangen."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private func permissionRow(_ title: String, _ detail: String, _ granted: Bool, _ action: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            Image(systemName: granted ? "checkmark.circle.fill" : "circle.dashed")
                .font(.title2).foregroundStyle(granted ? Brand.mint : .secondary)
                .contentTransition(.symbolEffect(.replace))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if !granted {
                Button(L("Erlauben …"), action: action).buttonStyle(.borderedProminent).tint(Brand.mint.opacity(0.85))
            }
        }
        .tafelCard(padding: 14)
    }

    private var source: some View {
        VStack(alignment: .leading, spacing: 14) {
            header("rectangle.dashed.badge.record", L("Was soll aufs iPad?"),
                   L("Lässt sich jederzeit im Tafel-Fenster umstellen."))
            HStack(spacing: 8) {
                ForEach(CaptureMode.allCases) { m in
                    let unavailable = m == .virtual && !HostController.secondScreenAvailable
                    ModeButton(mode: m, selected: host.mode == m) { host.mode = m }
                        .disabled(unavailable).opacity(unavailable ? 0.4 : 1)
                }
            }
            Text(host.mode.help).font(.callout).foregroundStyle(.secondary)
                .contentTransition(.opacity)
            Spacer()
        }
    }

    private var pairing: some View {
        VStack(alignment: .leading, spacing: 14) {
            header("ipad.and.arrow.forward", L("iPad koppeln"),
                   L("Öffne Tafel auf dem iPad, tippe unter „Neu koppeln“ auf diesen Mac und gib den Code ein."))
            if let paired = host.lastPaired, paired != pairedAtStart {
                Label(L("%@ ist gekoppelt.", paired), systemImage: "checkmark.seal.fill")
                    .font(.title3.weight(.semibold)).foregroundStyle(Brand.mint)
                    .tafelCard()
                    .transition(.scale.combined(with: .opacity))
            } else if let code = host.pairingCode {
                HStack(spacing: 18) {
                    CountdownRing(fraction: Double(host.pairingSecondsLeft) / 120, seconds: host.pairingSecondsLeft)
                        .frame(width: 54, height: 54)
                    Text(PairingCode.formatted(code))
                        .font(.system(size: 30, weight: .semibold, design: .monospaced))
                        .kerning(2)
                        .textSelection(.enabled)
                }
                .tafelCard()
                .transition(.scale(scale: 0.95).combined(with: .opacity))
            } else {
                Button {
                    host.beginPairing()
                } label: {
                    Label(L("Code anzeigen"), systemImage: "key.horizontal").padding(.horizontal, 6)
                }
                .buttonStyle(.borderedProminent).tint(Brand.mint.opacity(0.9)).controlSize(.large)
            }
            Text(L("Schon gekoppelt? Dann einfach „Fertig“ – das iPad verbindet sich von selbst."))
                .font(.caption).foregroundStyle(.secondary)
            Spacer()
        }
    }

    private func header(_ symbol: String, _ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: symbol).font(.system(size: 30, weight: .semibold)).foregroundStyle(Brand.mint)
            Text(title).font(.system(size: 26, weight: .bold, design: .rounded))
            Text(subtitle).foregroundStyle(.secondary)
        }
        .padding(.bottom, 6)
    }
}
