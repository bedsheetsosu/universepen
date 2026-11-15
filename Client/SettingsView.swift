import SwiftUI
import TafelKit

struct SettingsView: View {
    @EnvironmentObject var model: ClientModel
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var l10n = L10n.shared

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LanguageChoice()
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets())
                } header: {
                    Text(L("Sprache"))
                }
                connectionSection
                imageSection
                pencilSection
                gestureSection
                shortcutSection
                keyboardSection
                Section {
                    Toggle(L("Latenz dauerhaft anzeigen"), isOn: $model.showStatusOverlay)
                    Toggle(L("Shortcut-Leiste rechts (Linkshänder)"), isOn: $model.settings.shortcutBarOnRight)
                    Button(L("Einrichtung erneut starten")) {
                        dismiss()
                        model.onboardingDone = false
                    }
                }
            }
            .navigationTitle(L("Einstellungen"))
            .toolbar { Button(L("Fertig")) { dismiss() } }
        }
    }

    private var connectionSection: some View {
        Section {
            LabeledContent("Mac", value: model.hostInfo?.hostName ?? "–")
            LabeledContent(L("Quelle"), value: model.hostInfo?.sourceDescription.isEmpty == false ? model.hostInfo!.sourceDescription : "–")
            if let t = model.timing {
                LabeledContent(L("Weg"), value: localizedLink(t.link))
                LabeledContent(L("Netz-RTT"), value: "\(Int(t.rttMs.rounded())) ms")
                if let a = t.frameAgeMs { LabeledContent(L("Bildalter bei Empfang"), value: "\(Int(a.rounded())) ms") }
                LabeledContent(L("Empfangen"), value: L("%d Bilder/s", Int(t.fps)))
            }
            if let id = model.hostInfo?.hostID, let p = model.paired.first(where: { $0.id == id }) {
                LabeledContent(L("Schlüssel-Fingerabdruck"), value: p.fingerprint)
            }
            LabeledContent(L("Kabel-Kandidat"), value: model.cableInterface?.name ?? L("keiner"))
            LabeledContent(L("Sichtbare Schnittstellen"), value: model.visibleInterfaces.isEmpty ? "–" : model.visibleInterfaces)
            Toggle(L("Peer-to-Peer-WLAN (ohne Router)"), isOn: $model.peerToPeer)
            Button(L("Neu verbinden")) { model.retry() }
            Button(L("Trennen"), role: .destructive) { model.disconnect(); dismiss() }
        } header: {
            Text(L("Verbindung"))
        } footer: {
            Text(L("Mit USB-Kabel zum Mac verbindet Tafel zuerst über das Kabel und sonst über WLAN. Peer-to-Peer-WLAN nur einschalten, wenn kein gemeinsames WLAN da ist – es erhöht die Latenz."))
        }
    }

    private var keyboardSection: some View {
        Section {
            Toggle(L("Tasten ^ und < tauschen"), isOn: $model.settings.swapISOKeys)
            Toggle(L("Trackpad / Maus steuert den Mac"), isOn: $model.settings.trackpadAsMouse)
            Toggle(L("iPad-Zeiger ausblenden"), isOn: $model.settings.hideIPadPointer)
        } header: {
            Text(L("Tastatur & Trackpad"))
        } footer: {
            Text(L("Eine angeschlossene Tastatur (z. B. Logi Combo Touch) tippt direkt auf dem Mac – Taste für Taste, mit dem Tastaturlayout des Mac. Nicht übertragbar sind Kurzbefehle, die iPadOS selbst belegt (z. B. ⌘-Tab, ⌘-Leertaste, Globus-Taste). Trackpad: Zeigen, Klicken, Zwei-Finger-Klick = Rechtsklick, Zwei-Finger-Scrollen, Pinch = Zoom (Methode wie bei den Finger-Gesten). Die Bildschirmtastatur gibt es im …-Menü."))
        }
    }

    private var imageSection: some View {
        Section {
            Toggle(L("Ton vom Mac"), isOn: $model.quality.audio)
            Picker("Codec", selection: $model.quality.codec) {
                Text("H.264").tag(VideoCodec.h264)
                Text("HEVC").tag(VideoCodec.hevc)
            }
            Picker(L("Bildrate"), selection: $model.quality.fps) {
                Text("60 fps").tag(60)
                Text("30 fps").tag(30)
            }
            Picker(L("Auflösung"), selection: $model.quality.resolutionScale) {
                Text(L("Nativ (100 %)")).tag(1.0)
                Text("75 %").tag(0.75)
                Text("50 %").tag(0.5)
            }
            VStack(alignment: .leading) {
                Text(L("Bitrate: %d Mbit/s", Int(model.quality.bitrateMbps)))
                Slider(value: $model.quality.bitrateMbps, in: 5...100, step: 5)
            }
        } header: {
            Text(L("Bild"))
        } footer: {
            Text(L("Höhere Bitrate = schärfer, braucht aber stabiles WLAN. Bei Rucklern Bitrate senken oder 30 fps wählen."))
        }
    }

    private var pencilSection: some View {
        Section {
            VStack(alignment: .leading) {
                Text(L("Druckkurve: %.2f (%@)", model.settings.pressure.gamma,
                       model.settings.pressure.gamma < 1 ? L("weicher") : model.settings.pressure.gamma > 1 ? L("härter") : L("linear")))
                Slider(value: $model.settings.pressure.gamma, in: 0.3...3)
            }
            VStack(alignment: .leading) {
                Text(L("Mindestdruck: %.2f", model.settings.pressure.minimum))
                Slider(value: $model.settings.pressure.minimum, in: 0...0.2)
            }
            Toggle(L("Neigung X umkehren"), isOn: $model.settings.tilt.invertX)
            Toggle(L("Neigung Y umkehren"), isOn: $model.settings.tilt.invertY)
            Toggle(L("Schweben (Hover) senden"), isOn: $model.settings.sendHover)
            Toggle(L("Barrel Roll als Rotation senden"), isOn: $model.settings.sendRoll)
            ActionPicker(title: L("Doppeltippen"), action: $model.settings.doubleTap)
            ActionPicker(title: L("Squeeze"), action: $model.settings.squeeze)
        } header: {
            Text(L("Stift"))
        } footer: {
            Text(L("Ob Neigung und Rotation in einer Mac-App ankommen, hängt von der App ab. Bitte mit dem Testplan in der README prüfen."))
        }
    }

    private var gestureSection: some View {
        Section {
            Picker(L("Ein Finger"), selection: $model.settings.fingerMode) {
                ForEach(FingerMode.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            if model.settings.fingerMode == .pen {
                VStack(alignment: .leading) {
                    Text(L("Druck beim Finger: %d %%", Int(model.settings.fingerPressure * 100)))
                    Slider(value: $model.settings.fingerPressure, in: 0.1...1)
                }
            }
            if model.settings.fingerMode != .off {
                Toggle(L("Halten = Rechtsklick"), isOn: $model.settings.longPressRightClick)
                VStack(alignment: .leading) {
                    Text(L("Handballen-Erkennung: ab %d pt Auflagefläche", Int(model.settings.palmRadius)))
                    Slider(value: $model.settings.palmRadius, in: 15...60, step: 1)
                }
            }
            Toggle(L("Zwei Finger verschieben (Scrollen)"), isOn: $model.settings.panEnabled)
            Toggle(L("Verschieben umkehren"), isOn: $model.settings.invertPan)
            Picker(L("Zoomen (Pinch)"), selection: $model.settings.zoomMethod) {
                ForEach(ZoomMethod.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            if model.settings.zoomMethod != .keyboardSteps && model.settings.zoomMethod != .off {
                VStack(alignment: .leading) {
                    Text(L("Zoom-Empfindlichkeit"))
                    Slider(value: $model.settings.zoomSensitivity, in: 0.05...1)
                }
            }
            ActionPicker(title: L("Drehen links"), action: $model.settings.rotateLeft)
            ActionPicker(title: L("Drehen rechts"), action: $model.settings.rotateRight)
            Stepper(L("Drehschritt: %d°", Int(model.settings.rotateStepDegrees)), value: $model.settings.rotateStepDegrees, in: 5...90, step: 5)
            ActionPicker(title: L("Zwei-Finger-Tipp"), action: $model.settings.twoFingerTap)
            ActionPicker(title: L("Drei-Finger-Tipp"), action: $model.settings.threeFingerTap)
            ActionPicker(title: L("Vier-Finger-Tipp"), action: $model.settings.fourFingerTap)
            ActionPicker(title: L("Drei Finger nach links"), action: $model.settings.threeFingerSwipeLeft)
            ActionPicker(title: L("Drei Finger nach rechts"), action: $model.settings.threeFingerSwipeRight)
            ActionPicker(title: L("Drei Finger nach oben"), action: $model.settings.threeFingerSwipeUp)
            ActionPicker(title: L("Drei Finger nach unten"), action: $model.settings.threeFingerSwipeDown)
        } header: {
            Text(L("Finger & Multi-Touch"))
        } footer: {
            Text(L("Wie bei einem Stift-Display: Ein Finger tippt (Klick), zieht (Klicken und Ziehen – zeichnet ohne Druck) und hält (Rechtsklick). Liegt der Stift in der Nähe oder wurde gerade benutzt, und bei großer Auflagefläche (Handballen), lösen Finger nichts aus. Vier-Finger-Gesten fängt iPadOS ab, wenn in den iPad-Einstellungen Multitasking-Gesten aktiv sind."))
        }
    }

    private var shortcutSection: some View {
        Section {
            Toggle(L("Shortcut-Leiste anzeigen"), isOn: $model.settings.showShortcutBar)
            ForEach($model.settings.shortcutBar) { $b in
                NavigationLink {
                    Form {
                        TextField(L("Titel"), text: $b.title)
                        ShortcutEditor(shortcut: $b.shortcut)
                    }
                    .navigationTitle(b.title)
                } label: {
                    LabeledContent(b.title, value: b.shortcut.display)
                }
            }
            .onDelete { model.settings.shortcutBar.remove(atOffsets: $0) }
            .onMove { model.settings.shortcutBar.move(fromOffsets: $0, toOffset: $1) }
            Button(L("Taste hinzufügen")) {
                model.settings.shortcutBar.append(ShortcutButton(title: L("Neu"), shortcut: Shortcut("a")))
            }
        } header: {
            Text(L("Shortcuts"))
        } footer: {
            Text(L("Tasten werden auf dem Mac anhand des aktiven Tastaturlayouts aufgelöst (z. B. QWERTZ)."))
        }
    }
}

/// Picker for a configurable action with common Affinity presets + custom shortcut.
struct ActionPicker: View {
    let title: String
    @Binding var action: PencilAction

    private enum Preset: String, CaseIterable, Identifiable {
        case none, undo, redo, eraser, brush, hand, custom
        var id: String { rawValue }
        var label: String {
            switch self {
            case .none: return L("Keine")
            case .undo: return L("Widerrufen ⌘Z")
            case .redo: return L("Wiederholen ⇧⌘Z")
            case .eraser: return L("Radierer (E)")
            case .brush: return L("Pinsel (B)")
            case .hand: return L("Hand (H)")
            case .custom: return L("Eigener Shortcut")
            }
        }
        var action: PencilAction {
            switch self {
            case .none: return .none
            case .undo: return .undo
            case .redo: return .redo
            case .eraser: return .eraser
            case .brush: return .brush
            case .hand: return .hand
            case .custom: return .shortcut(Shortcut("a"))
            }
        }
    }

    private var preset: Binding<Preset> {
        Binding(get: {
            Preset.allCases.first { $0 != .custom && $0.action == action } ?? .custom
        }, set: { p in
            if p != .custom || action.shortcut == nil || Preset.allCases.contains(where: { $0 != .custom && $0.action == action }) {
                action = p.action
            }
        })
    }

    var body: some View {
        Picker(title, selection: preset) {
            ForEach(Preset.allCases) { Text($0.label).tag($0) }
        }
        if preset.wrappedValue == .custom, let s = action.shortcut {
            ShortcutEditor(shortcut: Binding(get: { s }, set: { action = .shortcut($0) }))
                .padding(.leading, 16)
        }
    }
}

struct ShortcutEditor: View {
    @Binding var shortcut: Shortcut

    private static let specials = ["esc", "delete", "tab", "space", "return", "left", "right", "up", "down"]

    var body: some View {
        HStack {
            Text(L("Taste"))
            Spacer()
            TextField(L("z. B. z, +, [, esc"), text: Binding(
                get: { shortcut.key },
                set: { v in
                    let t = v.trimmingCharacters(in: .whitespaces).lowercased()
                    if Self.specials.contains(t) { shortcut.key = t } else if let last = t.last { shortcut.key = String(last) }
                }))
            .multilineTextAlignment(.trailing)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .frame(maxWidth: 160)
        }
        HStack(spacing: 8) {
            modifierToggle("⌘", .command)
            modifierToggle("⇧", .shift)
            modifierToggle("⌥", .option)
            modifierToggle("⌃", .control)
            Spacer()
            Text(shortcut.display).font(.body.monospaced()).foregroundStyle(.secondary)
        }
    }

    private func modifierToggle(_ label: String, _ m: ModifierSet) -> some View {
        Toggle(label, isOn: Binding(
            get: { shortcut.modifiers.contains(m) },
            set: { on in if on { shortcut.modifiers.insert(m) } else { shortcut.modifiers.remove(m) } }))
        .toggleStyle(.button)
    }
}
