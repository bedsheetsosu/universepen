import SwiftUI
import TafelKit

/// Everything the Pencil, the fingers and the Mac shortcuts do right now, on one page.
struct CheatSheetView: View {
    @EnvironmentObject var model: ClientModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let s = model.effectiveSettings
        NavigationStack {
            List {
                Section(L("Pencil")) {
                    entry("applepencil.doubletap", L("Doppeltippen"), s.doubleTap.display)
                    entry("applepencil.squeeze", L("Squeeze"), s.squeeze.display)
                    if let k = s.squeezeHoldKey { entry("applepencil.squeeze", L("Squeeze halten"), k == .space ? L("Leertaste") : k.symbol) }
                    if s.shapeRecognition { entry("scribble.variable", L("Formerkennung"), L("Am Strichende kurz halten")) }
                    if s.ropeLength > 0 { entry("lasso", L("Seil-Stabilisator: %d pt", Int(s.ropeLength)), "") }
                }
                Section(L("Finger")) {
                    entry("hand.tap", L("Zwei-Finger-Tipp"), s.twoFingerTap.display)
                    entry("hand.tap", L("Drei-Finger-Tipp"), s.threeFingerTap.display)
                    entry("hand.tap", L("Vier-Finger-Tipp"), s.fourFingerTap.display)
                    entry("arrow.left", L("Drei Finger nach links"), s.threeFingerSwipeLeft.display)
                    entry("arrow.right", L("Drei Finger nach rechts"), s.threeFingerSwipeRight.display)
                    entry("arrow.up", L("Drei Finger nach oben"), s.threeFingerSwipeUp.display)
                    entry("arrow.down", L("Drei Finger nach unten"), s.threeFingerSwipeDown.display)
                    entry("arrow.up.left.and.arrow.down.right", L("Zoomen (Pinch)"), s.zoomMethod.title)
                    entry("rotate.right", L("Drehen links"), s.rotateLeft.display)
                    entry("rotate.left", L("Drehen rechts"), s.rotateRight.display)
                    if s.undoScrub { entry("arrow.uturn.backward", L("Undo-Wischen (zwei Finger halten, dann ziehen)"), "") }
                }
                Section(L("Mac")) {
                    entry("keyboard", "⌃⌥⌘T", L("Tablett-Modus"))
                    entry("keyboard", "⌃⌥⌘P", L("Palette fürs iPad wählen …"))
                    entry("keyboard", "⌃⌥⌘I", L("Vorderstes Fenster aufs iPad"))
                }
            }
            .themedForm()
            .navigationTitle(L("Gesten & Kürzel"))
            .toolbar { Button(L("Fertig")) { dismiss() } }
        }
    }

    private func entry(_ symbol: String, _ title: String, _ value: String) -> some View {
        LabeledContent {
            Text(value).foregroundStyle(.secondary)
        } label: {
            Label(title, systemImage: symbol)
        }
    }
}
