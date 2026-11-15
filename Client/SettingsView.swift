import SwiftUI
import TafelKit

struct SettingsView: View {
    @EnvironmentObject var model: ClientModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                connectionSection
                imageSection
                pencilSection
                gestureSection
                shortcutSection
                keyboardSection
                Section {
                    Toggle("Latenz dauerhaft anzeigen", isOn: $model.showStatusOverlay)
                }
            }
            .navigationTitle("Einstellungen")
            .toolbar { Button("Fertig") { dismiss() } }
        }
    }

    private var connectionSection: some View {
        Section {
            LabeledContent("Mac", value: model.hostInfo?.hostName ?? "–")
            LabeledContent("Quelle", value: model.hostInfo?.sourceDescription.isEmpty == false ? model.hostInfo!.sourceDescription : "–")
            if let t = model.timing {
                LabeledContent("Weg", value: t.link)
                LabeledContent("Netz-RTT", value: "\(Int(t.rttMs.rounded())) ms")
                if let a = t.frameAgeMs { LabeledContent("Bildalter bei Empfang", value: "\(Int(a.rounded())) ms") }
                LabeledContent("Empfangen", value: "\(Int(t.fps)) Bilder/s")
            }
            if let id = model.hostInfo?.hostID, let p = model.paired.first(where: { $0.id == id }) {
                LabeledContent("Schlüssel-Fingerabdruck", value: p.fingerprint)
            }
            LabeledContent("Kabel-Kandidat", value: model.cableInterface?.name ?? "keiner")
            LabeledContent("Sichtbare Schnittstellen", value: model.visibleInterfaces.isEmpty ? "–" : model.visibleInterfaces)
            Toggle("Peer-to-Peer-WLAN (ohne Router)", isOn: $model.peerToPeer)
            Button("Neu verbinden") { model.retry() }
            Button("Trennen", role: .destructive) { model.disconnect(); dismiss() }
        } header: {
            Text("Verbindung")
        } footer: {
            Text("Mit USB-Kabel zum Mac verbindet Tafel zuerst über das Kabel und sonst über WLAN. Peer-to-Peer-WLAN nur einschalten, wenn kein gemeinsames WLAN da ist – es erhöht die Latenz.")
        }
    }

    private var keyboardSection: some View {
        Section {
            Toggle("Tasten ^ und < tauschen", isOn: $model.settings.swapISOKeys)
            Toggle("Trackpad / Maus steuert den Mac", isOn: $model.settings.trackpadAsMouse)
            Toggle("iPad-Zeiger ausblenden", isOn: $model.settings.hideIPadPointer)
        } header: {
            Text("Tastatur & Trackpad")
        } footer: {
            Text("Eine angeschlossene Tastatur (z. B. Logi Combo Touch) tippt direkt auf dem Mac – Taste für Taste, mit dem Tastaturlayout des Mac. Nicht übertragbar sind Kurzbefehle, die iPadOS selbst belegt (z. B. ⌘-Tab, ⌘-Leertaste, Globus-Taste). Trackpad: Zeigen, Klicken, Zwei-Finger-Klick = Rechtsklick, Zwei-Finger-Scrollen, Pinch = Zoom (Methode wie bei den Finger-Gesten). Die Bildschirmtastatur gibt es im …-Menü.")
        }
    }

    private var imageSection: some View {
        Section {
            Toggle("Ton vom Mac", isOn: $model.quality.audio)
            Picker("Codec", selection: $model.quality.codec) {
                Text("H.264").tag(VideoCodec.h264)
                Text("HEVC").tag(VideoCodec.hevc)
            }
            Picker("Bildrate", selection: $model.quality.fps) {
                Text("60 fps").tag(60)
                Text("30 fps").tag(30)
            }
            Picker("Auflösung", selection: $model.quality.resolutionScale) {
                Text("Nativ (100 %)").tag(1.0)
                Text("75 %").tag(0.75)
                Text("50 %").tag(0.5)
            }
            VStack(alignment: .leading) {
                Text("Bitrate: \(Int(model.quality.bitrateMbps)) Mbit/s")
                Slider(value: $model.quality.bitrateMbps, in: 5...100, step: 5)
            }
        } header: {
            Text("Bild")
        } footer: {
            Text("Höhere Bitrate = schärfer, braucht aber stabiles WLAN. Bei Rucklern Bitrate senken oder 30 fps wählen.")
        }
    }

    private var pencilSection: some View {
        Section {
            VStack(alignment: .leading) {
                Text("Druckkurve: \(String(format: "%.2f", model.settings.pressure.gamma)) (\(model.settings.pressure.gamma < 1 ? "weicher" : model.settings.pressure.gamma > 1 ? "härter" : "linear"))")
                Slider(value: $model.settings.pressure.gamma, in: 0.3...3)
            }
            VStack(alignment: .leading) {
                Text("Mindestdruck: \(String(format: "%.2f", model.settings.pressure.minimum))")
                Slider(value: $model.settings.pressure.minimum, in: 0...0.2)
            }
            Toggle("Neigung X umkehren", isOn: $model.settings.tilt.invertX)
            Toggle("Neigung Y umkehren", isOn: $model.settings.tilt.invertY)
            Toggle("Schweben (Hover) senden", isOn: $model.settings.sendHover)
            Toggle("Barrel Roll als Rotation senden", isOn: $model.settings.sendRoll)
            ActionPicker(title: "Doppeltippen", action: $model.settings.doubleTap)
            ActionPicker(title: "Squeeze", action: $model.settings.squeeze)
        } header: {
            Text("Stift")
        } footer: {
            Text("Ob Neigung und Rotation in einer Mac-App ankommen, hängt von der App ab. Bitte mit dem Testplan in der README prüfen.")
        }
    }

    private var gestureSection: some View {
        Section("Finger-Gesten") {
            Toggle("Zwei Finger verschieben (Scrollen)", isOn: $model.settings.panEnabled)
            Toggle("Verschieben umkehren", isOn: $model.settings.invertPan)
            Picker("Zoomen (Pinch)", selection: $model.settings.zoomMethod) {
                ForEach(ZoomMethod.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            if model.settings.zoomMethod != .keyboardSteps && model.settings.zoomMethod != .off {
                VStack(alignment: .leading) {
                    Text("Zoom-Empfindlichkeit")
                    Slider(value: $model.settings.zoomSensitivity, in: 0.05...1)
                }
            }
            ActionPicker(title: "Drehen links", action: $model.settings.rotateLeft)
            ActionPicker(title: "Drehen rechts", action: $model.settings.rotateRight)
            Stepper("Drehschritt: \(Int(model.settings.rotateStepDegrees))°", value: $model.settings.rotateStepDegrees, in: 5...90, step: 5)
            ActionPicker(title: "Zwei-Finger-Tipp", action: $model.settings.twoFingerTap)
            ActionPicker(title: "Drei-Finger-Tipp", action: $model.settings.threeFingerTap)
        }
    }

    private var shortcutSection: some View {
        Section {
            Toggle("Shortcut-Leiste anzeigen", isOn: $model.settings.showShortcutBar)
            ForEach($model.settings.shortcutBar) { $b in
                NavigationLink {
                    Form {
                        TextField("Titel", text: $b.title)
                        ShortcutEditor(shortcut: $b.shortcut)
                    }
                    .navigationTitle(b.title)
                } label: {
                    LabeledContent(b.title, value: b.shortcut.display)
                }
            }
            .onDelete { model.settings.shortcutBar.remove(atOffsets: $0) }
            .onMove { model.settings.shortcutBar.move(fromOffsets: $0, toOffset: $1) }
            Button("Taste hinzufügen") {
                model.settings.shortcutBar.append(ShortcutButton(title: "Neu", shortcut: Shortcut("a")))
            }
        } header: {
            Text("Shortcuts")
        } footer: {
            Text("Tasten werden auf dem Mac anhand des aktiven Tastaturlayouts aufgelöst (z. B. QWERTZ).")
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
            case .none: return "Keine"
            case .undo: return "Widerrufen ⌘Z"
            case .redo: return "Wiederholen ⇧⌘Z"
            case .eraser: return "Radierer (E)"
            case .brush: return "Pinsel (B)"
            case .hand: return "Hand (H)"
            case .custom: return "Eigener Shortcut"
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
            Text("Taste")
            Spacer()
            TextField("z. B. z, +, [, esc", text: Binding(
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
