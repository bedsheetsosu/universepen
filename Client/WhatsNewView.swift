import SwiftUI
import TafelKit

/// Shown once after updating to a version with new features.
struct WhatsNewView: View {
    @Environment(\.dismiss) private var dismiss
    static let version = "0.8.0"
    static let seenKey = "whatsNewSeen"

    static var shouldShow: Bool {
        // Not on a fresh install (onboarding explains everything), only after an update.
        guard UserDefaults.standard.object(forKey: "pairedHosts") != nil else {
            UserDefaults.standard.set(version, forKey: seenKey)
            return false
        }
        return UserDefaults.standard.string(forKey: seenKey) != version
    }

    static func markSeen() { UserDefaults.standard.set(version, forKey: seenKey) }

    private let items: [(String, String, String)] = [
        ("paintpalette", L("Farbtreue"), L("10-Bit-Farbe und die richtige Tonkurve – Schatten und Verläufe wie am Mac.")),
        ("perspective", L("Zeichenhilfen"), L("Perspektive mit 1–3 Fluchtpunkten, Ellipsen-Schablone, Raster – jede App merkt sich ihre.")),
        ("scribble.variable", L("Formerkennung"), L("Am Strichende kurz halten: Linie, Pfeil, Kreis, Rechteck werden sauber.")),
        ("lasso", L("Ruhige Linien"), L("Seil-Stabilisator, Tempo-Druck, fester Druck und Druckkurven-Vorlagen.")),
        ("rotate.right", L("Ansicht"), L("Drehen wie ein Blatt Papier, spiegeln, Graustufen – nur auf dem iPad.")),
        ("square.on.square.dashed", L("Paletten-Fenster"), L("Ein Mac-Bereich schwebt live auf dem iPad und lässt sich antippen.")),
        ("applepencil.squeeze", L("Squeeze halten"), L("Hält eine Taste, solange du drückst – z. B. Leertaste zum Verschieben.")),
        ("rectangle.dashed", L("Tablett-Modus automatisch"), L("Schaltet sich für gewählte Apps wie osu! von selbst ein.")),
        ("square.stack.3d.up", L("Kurzbefehle"), L("Verbinden, Werkzeuge und Tablett-Modus aus Kurzbefehle, Siri und Kontrollzentrum.")),
        ("thermometer.medium", L("Hitzeschutz"), L("Wird der Mac heiß, drosselt sich der Stream – abgedunkelt pausiert er ganz.")),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(L("Neu in %@", Self.version)).font(.largeTitle.bold())
                    ForEach(items, id: \.1) { icon, title, text in
                        HStack(alignment: .top, spacing: 14) {
                            Image(systemName: icon).font(.title2).foregroundStyle(Brand.mint).frame(width: 34)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(title).font(.headline)
                                Text(text).foregroundStyle(.secondary)
                            }
                        }
                    }
                    Text(L("Alles Weitere: … → Gesten & Kürzel und die Einstellungen."))
                        .font(.footnote).foregroundStyle(.secondary)
                }
                .padding(28)
            }
            .toolbar { Button(L("Los geht's")) { Self.markSeen(); dismiss() } }
        }
    }
}
