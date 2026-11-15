import SwiftUI
import TafelKit

/// First-run setup: explains the connection and sets the most important preferences.
/// Everything chosen here can be changed later in Settings.
struct OnboardingView: View {
    /// Redraw when the colours change.
    @ObservedObject var theme = Theme.shared
    @EnvironmentObject var model: ClientModel
    @State private var step = 0
    @State private var forward = true

    private let steps = 7

    var body: some View {
        ZStack {
            ThemeBackground().ignoresSafeArea()
            VStack(spacing: 0) {
                ZStack {
                    page(step)
                        .id(step)
                        .transition(.asymmetric(
                            insertion: .move(edge: forward ? .trailing : .leading).combined(with: .opacity),
                            removal: .move(edge: forward ? .leading : .trailing).combined(with: .opacity)))
                }
                .frame(maxWidth: 640, maxHeight: .infinity)
                .padding(.horizontal, 28)
                footer
            }
        }
        .animation(.spring(response: 0.5, dampingFraction: 0.86), value: step)
    }

    @ViewBuilder private func page(_ i: Int) -> some View {
        switch i {
        case 0: language
        case 1: welcome
        case 2: connection
        case 3: pencil
        case 4: fingers
        case 5: picture
        default: hand
        }
    }

    // MARK: Footer: progress + navigation

    private var footer: some View {
        HStack {
            Button(L("Zurück")) { go(-1) }
                .opacity(step == 0 ? 0 : 1)
                .disabled(step == 0)
            Spacer()
            HStack(spacing: 8) {
                ForEach(0..<steps, id: \.self) { i in
                    Capsule()
                        .fill(i == step ? Brand.mint : .white.opacity(0.2))
                        .frame(width: i == step ? 22 : 8, height: 8)
                }
            }
            Spacer()
            Button {
                if step == steps - 1 { model.onboardingDone = true } else { go(1) }
            } label: {
                Text(step == steps - 1 ? L("Los geht’s") : L("Weiter"))
                    .fontWeight(.semibold)
                    .foregroundStyle(Brand.slateDeep)
                    .padding(.horizontal, 22).padding(.vertical, 11)
                    .background(Brand.mint, in: Capsule())
            }
            .buttonStyle(PressScale())
        }
        .frame(maxWidth: 640)
        .padding(.horizontal, 28)
        .padding(.bottom, 28)
    }

    private func go(_ d: Int) {
        forward = d > 0
        step = max(0, min(steps - 1, step + d))
    }

    // MARK: Pages

    private var language: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "globe")
                .font(.system(size: 48, weight: .semibold))
                .foregroundStyle(Brand.mint)
            Text("Language · Sprache")
                .font(.system(size: 36, weight: .bold, design: .rounded))
            Text("Choose your language. · Wähle deine Sprache.")
                .font(.title3).foregroundStyle(.secondary)
            LanguageChoice().frame(maxWidth: 560)
            Spacer()
        }
    }

    private var welcome: some View {
        VStack(spacing: 22) {
            Spacer()
            ZStack {
                PulseRings(color: Brand.mint).frame(width: 150, height: 150)
                TafelMark().frame(width: 120, height: 120)
                    .shadow(color: Brand.mint.opacity(0.4), radius: 30)
            }
            Text(L("Willkommen bei UniversePen"))
                .font(.system(size: 40, weight: .bold, design: .rounded))
            Text(L("Dein iPad wird zum Zeichendisplay für den Mac – mit Pencil-Druck und Neigung, Fingern, Tastatur und Trackpad. Ohne Konto, ohne Cloud, kostenlos."))
                .font(.title3).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Text(L("Ein paar Fragen, dann passt alles. Du kannst später alles in den Einstellungen ändern."))
                .font(.callout).foregroundStyle(.tertiary).multilineTextAlignment(.center)
            Spacer()
        }
    }

    private var connection: some View {
        PageScaffold(symbol: "cable.connector", title: L("So verbindet sich UniversePen"),
                     subtitle: L("Auf dem Mac läuft die App „UniversePen Host“. Beim ersten Mal koppelst du beide mit einem Code.")) {
            InfoRow(symbol: "cable.connector", title: L("USB-Kabel (empfohlen)"),
                    text: L("Geringste Latenz. UniversePen nimmt automatisch das Kabel, sobald es steckt."))
            InfoRow(symbol: "wifi", title: L("WLAN"),
                    text: L("Funktioniert auch ohne Kabel, wenn Mac und iPad im selben WLAN sind."))
            InfoRow(symbol: "lock.shield", title: L("Verschlüsselt und privat"),
                    text: L("Nur gekoppelte Geräte, direkt zwischen Mac und iPad – keine Server."))
            InfoRow(symbol: "network", title: L("Lokales Netzwerk"),
                    text: L("iPadOS fragt gleich, ob UniversePen Geräte im lokalen Netzwerk finden darf. Bitte erlauben – sonst findet das iPad den Mac nicht."))
        }
    }

    private var pencil: some View {
        PageScaffold(symbol: "applepencil.tip", title: L("Dein Pencil"),
                     subtitle: L("Wie soll sich der Druck anfühlen, und was machen die Pencil-Gesten?")) {
            ChoiceRow(title: L("Druckgefühl"), options: [
                (L("Weich"), "feather", 0.6), (L("Normal"), "pencil", 1.0), (L("Fest"), "pencil.tip", 1.6),
            ], selected: closest(model.settings.pressure.gamma, in: [0.6, 1.0, 1.6])) { model.settings.pressure.gamma = $0; model.settings.pressure.points = [] }
            ActionChoice(title: L("Doppeltippen"), action: $model.settings.doubleTap)
            ActionChoice(title: L("Squeeze (Pencil Pro)"), action: $model.settings.squeeze)
            Toggle(L("Schweben anzeigen (Hover)"), isOn: $model.settings.sendHover).tint(Brand.mint)
                .tafelCard(padding: 14)
            Toggle(L("Doppeltippen zum Klicken (Pencil ohne Hover)"), isOn: $model.settings.doubleTapToClick).tint(Brand.mint)
                .tafelCard(padding: 14)
        }
    }

    private var fingers: some View {
        PageScaffold(symbol: "hand.point.up.left", title: L("Und deine Finger?"),
                     subtitle: L("Wie bei einem Stift-Display. Liegt der Pencil in der Nähe, ignoriert UniversePen die Hand.")) {
            ChoiceRow(title: L("Ein Finger"), options: [
                (L("Maus"), "cursorarrow.click", FingerMode.mouse),
                (L("Stift"), "scribble", FingerMode.pen),
                (L("Zeiger"), "hand.point.up", FingerMode.pointer),
                (L("Aus"), "hand.raised.slash", FingerMode.off),
            ], selected: model.settings.fingerMode) { model.settings.fingerMode = $0 }
            Text(fingerHelp).font(.callout).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentTransition(.opacity)
            InfoRow(symbol: "hand.draw", title: L("Zwei Finger"),
                    text: L("Verschieben = Scrollen, Pinch = Zoomen, Tippen = Widerrufen."))
            InfoRow(symbol: "hand.wave", title: L("Drei Finger"),
                    text: L("Links/rechts wischen = Schreibtisch wechseln, oben = Mission Control, unten = App-Fenster."))
        }
    }

    private var fingerHelp: String {
        switch model.settings.fingerMode {
        case .mouse: return L("Tippen = Klick, Ziehen = Klicken und Ziehen, Halten = Rechtsklick.")
        case .pen: return L("Ein Finger zeichnet wie der Pencil, mit festem Druck. Halten = Rechtsklick.")
        case .off: return L("Ein Finger macht nichts – nur Gesten mit mehreren Fingern.")
        case .pointer: return L("Ein Finger bewegt nur den Zeiger, Tippen = Klick, Halten = Rechtsklick. Gut für Pencils ohne Schweben: mit dem Finger zielen, mit dem Stift zeichnen.")
        }
    }

    private var picture: some View {
        PageScaffold(symbol: "sparkles.tv", title: L("Bild und Ton"),
                     subtitle: L("Mit Kabel ist „Beste Qualität“ meist kein Problem. Im WLAN hilft „Flüssig“ gegen Ruckler.")) {
            ChoiceRow(title: L("Qualität"), options: QualityPreset.allCases.map { ($0.title, $0.symbol, $0) },
                      selected: QualityPreset(matching: model.quality)) { model.quality = $0.apply(to: model.quality) }
            Text(QualityPreset(matching: model.quality)?.detail ?? L("Eigene Einstellung"))
                .font(.callout).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Toggle(L("Ton vom Mac auf dem iPad"), isOn: $model.quality.audio).tint(Brand.mint)
                .tafelCard(padding: 14)
            Toggle(L("Latenz immer anzeigen"), isOn: $model.showStatusOverlay).tint(Brand.mint)
                .tafelCard(padding: 14)
        }
    }

    private var hand: some View {
        PageScaffold(symbol: "hand.raised", title: L("Mit welcher Hand zeichnest du?"),
                     subtitle: L("Die Shortcut-Leiste kommt auf die andere Seite, damit die Hand sie nicht verdeckt.")) {
            ChoiceRow(title: L("Zeichenhand"), options: [
                (L("Rechts"), "hand.point.right", false), (L("Links"), "hand.point.left", true),
            ], selected: model.settings.shortcutBarOnRight) { model.settings.shortcutBarOnRight = $0 }
            Toggle(L("Shortcut-Leiste anzeigen"), isOn: $model.settings.showShortcutBar).tint(Brand.mint)
                .tafelCard(padding: 14)
            InfoRow(symbol: "keyboard", title: L("Tastatur und Trackpad"),
                    text: L("Eine angeschlossene Tastatur tippt direkt auf dem Mac, das Trackpad steuert den Mac-Zeiger."))
        }
    }

    private func closest(_ v: Double, in options: [Double]) -> Double? {
        options.min(by: { abs($0 - v) < abs($1 - v) })
    }
}

// MARK: - Quality presets

enum QualityPreset: CaseIterable, Hashable {
    case best, balanced, smooth

    var title: String {
        switch self {
        case .best: return L("Beste")
        case .balanced: return L("Ausgewogen")
        case .smooth: return L("Flüssig")
        }
    }
    var symbol: String {
        switch self {
        case .best: return "sparkles"
        case .balanced: return "dial.medium"
        case .smooth: return "hare"
        }
    }
    var detail: String {
        switch self {
        case .best: return L("HEVC, 50 Mbit/s, 60 fps, volle iPad-Auflösung – ideal mit Kabel.")
        case .balanced: return L("H.264, 30 Mbit/s, 60 fps, volle Auflösung.")
        case .smooth: return L("H.264, 15 Mbit/s, 60 fps, 75 % Auflösung – für schwaches WLAN.")
        }
    }
    private var values: (VideoCodec, Double, Int, Double) {
        switch self {
        case .best: return (.hevc, 50, 60, 1)
        case .balanced: return (.h264, 30, 60, 1)
        case .smooth: return (.h264, 15, 60, 0.75)
        }
    }
    init?(matching q: StreamQuality) {
        guard let p = Self.allCases.first(where: { let v = $0.values; return q.codec == v.0 && q.bitrateMbps == v.1 && q.fps == v.2 && q.resolutionScale == v.3 })
        else { return nil }
        self = p
    }
    func apply(to q: StreamQuality) -> StreamQuality {
        var q = q
        (q.codec, q.bitrateMbps, q.fps, q.resolutionScale) = values
        return q
    }
}

// MARK: - Building blocks

private struct PageScaffold<Content: View>: View {
    /// Redraw when the colours change.
    @ObservedObject var theme = Theme.shared
    let symbol: String
    let title: String
    let subtitle: String
    @ViewBuilder var content: Content
    @State private var shown = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Image(systemName: symbol)
                    .font(.system(size: 40, weight: .semibold))
                    .foregroundStyle(Brand.mint)
                    .symbolEffect(.bounce, value: shown)
                    .padding(.top, 56)
                Text(title).font(.system(size: 34, weight: .bold, design: .rounded))
                Text(subtitle).font(.title3).foregroundStyle(.secondary)
                    .padding(.bottom, 8)
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .onAppear { shown = true }
    }
}

private struct InfoRow: View {
    /// Redraw when the colours change.
    @ObservedObject var theme = Theme.shared
    let symbol: String
    let title: String
    let text: String
    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.title3).foregroundStyle(Brand.mint)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(text).font(.callout).foregroundStyle(.secondary)
            }
        }
        .tafelCard(padding: 14)
    }
}

/// Big tappable choice tiles.
private struct ChoiceRow<Value: Hashable>: View {
    /// Redraw when the colours change.
    @ObservedObject var theme = Theme.shared
    let title: String
    let options: [(String, String, Value)]
    let selected: Value?
    let choose: (Value) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline).foregroundStyle(Brand.mintBright)
            HStack(spacing: 10) {
                ForEach(options.indices, id: \.self) { i in
                    let (label, symbol, value) = options[i]
                    let on = value == selected
                    Button {
                        withAnimation(Brand.spring) { choose(value) }
                    } label: {
                        VStack(spacing: 8) {
                            Image(systemName: symbol)
                                .font(.system(size: 24))
                                .symbolEffect(.bounce, value: on)
                            Text(label).font(.callout.weight(.semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .foregroundStyle(on ? Brand.slateDeep : .primary)
                        .background(on ? AnyShapeStyle(Brand.mint) : AnyShapeStyle(Color.white.opacity(0.06)),
                                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(.white.opacity(on ? 0 : 0.08)))
                    }
                    .buttonStyle(PressScale())
                }
            }
        }
    }
}

/// Compact choice of the common Pencil actions.
private struct ActionChoice: View {
    /// Redraw when the colours change.
    @ObservedObject var theme = Theme.shared
    let title: String
    @Binding var action: PencilAction

    private let options: [(String, PencilAction)] = [
        (L("Radierer"), .eraser), (L("Widerrufen"), .undo), (L("Pinsel"), .brush), (L("Hand"), .hand), (L("Nichts"), .none),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline).foregroundStyle(Brand.mintBright)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(options.indices, id: \.self) { i in
                        let (label, value) = options[i]
                        let on = value == action
                        Button {
                            withAnimation(Brand.spring) { action = value }
                        } label: {
                            Text(label)
                                .font(.callout.weight(.medium))
                                .padding(.horizontal, 16).padding(.vertical, 10)
                                .foregroundStyle(on ? Brand.slateDeep : .primary)
                                .background(on ? AnyShapeStyle(Brand.mint) : AnyShapeStyle(Color.white.opacity(0.06)), in: Capsule())
                        }
                        .buttonStyle(PressScale())
                    }
                }
            }
        }
    }
}
