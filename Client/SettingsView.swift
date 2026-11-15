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
                radialSection
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
            Text(L("Mit USB-Kabel zum Mac verbindet UniversePen zuerst über das Kabel und sonst über WLAN. Peer-to-Peer-WLAN nur einschalten, wenn kein gemeinsames WLAN da ist – es erhöht die Latenz."))
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
            Toggle(L("Bitrate automatisch anpassen"), isOn: $model.quality.adaptive)
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
            Toggle(L("Volle Mac-Auflösung senden"), isOn: $model.quality.fullSource)
            VStack(alignment: .leading) {
                Text(L("Bitrate: %d Mbit/s", Int(model.quality.bitrateMbps)))
                Slider(value: $model.quality.bitrateMbps, in: 5...100, step: 5)
            }
        } header: {
            Text(L("Bild"))
        } footer: {
            Text(L("Höhere Bitrate = schärfer, braucht aber stabiles WLAN. Bei Rucklern Bitrate senken oder 30 fps wählen.") + " " +
                 L("„Volle Mac-Auflösung“: Der Mac schickt alle Pixel unverkleinert (z. B. beim zweiten Bildschirm mit mehr Platz), das iPad verkleinert beim Anzeigen. Kann schärfer sein, braucht aber mehr Bitrate."))
        }
    }

    /// "" = standard Pencil settings, otherwise the bundle ID of a Mac app with its own profile.
    @State private var penTarget = ""

    private var penApps: [(id: String, name: String)] {
        var ids = Set(model.settings.appPenProfiles.keys)
        if let f = model.frontApp { ids.insert(f.bundleID) }
        return ids.map { id in (id, model.settings.appNames[id] ?? (model.frontApp?.bundleID == id ? model.frontApp!.name : id)) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var targetHasOwnProfile: Bool { !penTarget.isEmpty && model.settings.appPenProfiles[penTarget] != nil }

    private var pen: Binding<PenProfile> {
        Binding(get: {
            penTarget.isEmpty ? model.settings.penProfile : (model.settings.appPenProfiles[penTarget] ?? model.settings.penProfile)
        }, set: { v in
            if penTarget.isEmpty { model.settings.penProfile = v } else { model.settings.appPenProfiles[penTarget] = v }
        })
    }

    private var pencilSection: some View {
        Section {
            Picker(L("Einstellungen für"), selection: $penTarget) {
                Text(L("Standard (alle Apps)")).tag("")
                ForEach(penApps, id: \.id) { app in
                    Text(model.settings.appPenProfiles[app.id] == nil ? app.name : "\(app.name) ★").tag(app.id)
                }
            }
            if !penTarget.isEmpty && !targetHasOwnProfile {
                Button(L("Eigenes Stift-Profil für diese App anlegen")) {
                    model.settings.appPenProfiles[penTarget] = model.settings.penProfile
                    model.settings.appNames[penTarget] = penApps.first { $0.id == penTarget }?.name
                }
            } else {
                NavigationLink {
                    Form {
                        Section {
                            PressureCurveEditor(curve: pen.pressure)
                                .listRowBackground(Color.clear)
                        } footer: {
                            Text(L("Punkte mit dem Finger ziehen. Unten mit dem Pencil drücken, um zu sehen, wo dein Druck auf der Kurve landet."))
                        }
                    }
                    .navigationTitle(L("Druckkurve"))
                } label: {
                    LabeledContent(L("Druckkurve"), value: pen.wrappedValue.pressure.points.isEmpty ? L("Voreinstellung") : L("Eigene Kurve"))
                }
                VStack(alignment: .leading) {
                    Text(L("Strich glätten: %d %%", Int(pen.wrappedValue.positionSmoothing * 100)))
                    Slider(value: pen.positionSmoothing, in: 0...1)
                }
                VStack(alignment: .leading) {
                    Text(L("Druck glätten: %d %%", Int(pen.wrappedValue.pressureSmoothing * 100)))
                    Slider(value: pen.pressureSmoothing, in: 0...1)
                }
                VStack(alignment: .leading) {
                    Text(L("Mindestdruck: %.2f", pen.wrappedValue.pressure.minimum))
                    Slider(value: pen.pressure.minimum, in: 0...0.2)
                }
                ActionPicker(title: L("Doppeltippen"), action: pen.doubleTap)
                ActionPicker(title: L("Squeeze"), action: pen.squeeze)
                if targetHasOwnProfile {
                    Button(L("Eigenes Stift-Profil löschen"), role: .destructive) {
                        model.settings.appPenProfiles[penTarget] = nil
                        if model.settings.appShortcutBars[penTarget] == nil { model.settings.appNames[penTarget] = nil }
                        penTarget = ""
                    }
                }
            }
            Toggle(L("Neigung X umkehren"), isOn: $model.settings.tilt.invertX)
            Toggle(L("Neigung Y umkehren"), isOn: $model.settings.tilt.invertY)
            Toggle(L("Schweben (Hover) senden"), isOn: $model.settings.sendHover)
            Toggle(L("Barrel Roll als Rotation senden"), isOn: $model.settings.sendRoll)
        } header: {
            Text(L("Stift"))
        } footer: {
            Text(L("Druckkurve, Glättung, Doppeltippen und Squeeze können pro Mac-App eigene Werte haben (★) und wechseln automatisch mit der App, die am Mac vorne ist. Ob Neigung und Rotation in einer Mac-App ankommen, hängt von der App ab."))
        }
    }

    private var radialSection: some View {
        Section {
            ForEach($model.settings.radialMenu) { $b in
                NavigationLink {
                    ShortcutButtonEditor(button: $b)
                } label: {
                    LabeledContent(b.title, value: b.shortcut.display)
                }
            }
            .onDelete { idx in
                guard model.settings.radialMenu.count - idx.count >= 2 else { return }
                model.settings.radialMenu.remove(atOffsets: idx)
            }
            .onMove { model.settings.radialMenu.move(fromOffsets: $0, toOffset: $1) }
            if model.settings.radialMenu.count < InputSettings.maxRadialItems {
                Button(L("Aktion hinzufügen")) {
                    model.settings.radialMenu.append(ShortcutButton(title: L("Neu"), shortcut: Shortcut("a")))
                }
            }
            Button(L("Auf Standard zurücksetzen")) { model.settings.radialMenu = InputSettings.defaultRadialMenu }
        } header: {
            Text(L("Radialmenü"))
        } footer: {
            Text(L("Squeeze oder Doppeltippen auf „Radialmenü“ stellen. Dann erscheint an der Stiftspitze ein Ring: mit dem Pencil darüber schweben und nochmal drücken, oder antippen. Mitte oder daneben tippen schließt ihn. 2 bis 8 Aktionen, oben beginnend im Uhrzeigersinn."))
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

    /// "" = standard bar, otherwise the bundle ID of a Mac app with its own bar.
    @State private var barTarget = ""

    private var barApps: [(id: String, name: String)] {
        var ids = Set(model.settings.appShortcutBars.keys)
        if let f = model.frontApp { ids.insert(f.bundleID) }
        return ids.map { id in (id, model.settings.appNames[id] ?? (model.frontApp?.bundleID == id ? model.frontApp!.name : id)) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var targetHasOwnBar: Bool { !barTarget.isEmpty && model.settings.appShortcutBars[barTarget] != nil }

    private var bar: Binding<[ShortcutButton]> {
        Binding(get: {
            barTarget.isEmpty ? model.settings.shortcutBar : (model.settings.appShortcutBars[barTarget] ?? model.settings.shortcutBar)
        }, set: { v in
            if barTarget.isEmpty { model.settings.shortcutBar = v } else { model.settings.appShortcutBars[barTarget] = v }
        })
    }

    private var shortcutSection: some View {
        Section {
            Toggle(L("Shortcut-Leiste anzeigen"), isOn: $model.settings.showShortcutBar)
            Picker(L("Leiste für"), selection: $barTarget) {
                Text(L("Standard (alle Apps)")).tag("")
                ForEach(barApps, id: \.id) { app in
                    Text(model.settings.appShortcutBars[app.id] == nil ? app.name : "\(app.name) ★").tag(app.id)
                }
            }
            if !barTarget.isEmpty && !targetHasOwnBar {
                Button(L("Eigene Leiste für diese App anlegen")) {
                    model.settings.appShortcutBars[barTarget] = model.settings.shortcutBar
                    model.settings.appNames[barTarget] = barApps.first { $0.id == barTarget }?.name
                }
            } else {
                ForEach(bar) { $b in
                    NavigationLink {
                        ShortcutButtonEditor(button: $b)
                    } label: {
                        LabeledContent(b.title, value: b.hold.map { L("Halten: %@", $0.symbol) } ?? b.shortcut.display)
                    }
                }
                .onDelete { bar.wrappedValue.remove(atOffsets: $0) }
                .onMove { bar.wrappedValue.move(fromOffsets: $0, toOffset: $1) }
                Button(L("Taste hinzufügen")) {
                    bar.wrappedValue.append(ShortcutButton(title: L("Neu"), shortcut: Shortcut("a")))
                }
                if targetHasOwnBar {
                    Button(L("Eigene Leiste löschen"), role: .destructive) {
                        model.settings.appShortcutBars[barTarget] = nil
                        model.settings.appNames[barTarget] = nil
                        barTarget = ""
                    }
                }
            }
        } header: {
            Text(L("Shortcuts"))
        } footer: {
            Text(L("Die Leiste wechselt automatisch mit der App, die am Mac vorne ist (★ = eigene Leiste). Halte-Tasten (⇧ ⌥ ⌘ ⌃ Leertaste) bleiben gedrückt, solange der Finger darauf liegt – zum Beispiel ⇧ beim Zeichnen gerader Linien. Tasten werden auf dem Mac anhand des aktiven Tastaturlayouts aufgelöst."))
        }
    }
}

/// Picker for a configurable action with common Affinity presets + custom shortcut.
struct ActionPicker: View {
    let title: String
    @Binding var action: PencilAction

    private enum Preset: String, CaseIterable, Identifiable {
        case none, radialMenu, undo, redo, eraser, brush, hand, desktopLeft, desktopRight, missionControl, appWindows, custom
        var id: String { rawValue }
        var label: String {
            switch self {
            case .none: return L("Keine")
            case .radialMenu: return L("Radialmenü")
            case .undo: return L("Widerrufen ⌘Z")
            case .redo: return L("Wiederholen ⇧⌘Z")
            case .eraser: return L("Radierer (E)")
            case .brush: return L("Pinsel (B)")
            case .hand: return L("Hand (H)")
            case .desktopLeft: return L("Schreibtisch links ⌃←")
            case .desktopRight: return L("Schreibtisch rechts ⌃→")
            case .missionControl: return L("Mission Control ⌃↑")
            case .appWindows: return L("App-Fenster ⌃↓")
            case .custom: return L("Eigener Shortcut")
            }
        }
        var action: PencilAction {
            switch self {
            case .none: return .none
            case .radialMenu: return .radialMenu
            case .undo: return .undo
            case .redo: return .redo
            case .eraser: return .eraser
            case .brush: return .brush
            case .hand: return .hand
            case .desktopLeft: return .desktopLeft
            case .desktopRight: return .desktopRight
            case .missionControl: return .missionControl
            case .appWindows: return .appWindows
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

/// Edits one bar button: title, and either a shortcut or a key to hold.
struct ShortcutButtonEditor: View {
    @Binding var button: ShortcutButton

    var body: some View {
        Form {
            TextField(L("Titel"), text: $button.title)
            Picker(L("Art"), selection: Binding(get: { button.hold == nil ? 0 : 1 },
                                                set: { button.hold = $0 == 0 ? nil : (button.hold ?? .shift) })) {
                Text(L("Shortcut senden")).tag(0)
                Text(L("Taste halten")).tag(1)
            }
            .pickerStyle(.segmented)
            if button.hold != nil {
                Picker(L("Taste"), selection: Binding(get: { button.hold ?? .shift }, set: { button.hold = $0 })) {
                    ForEach(HoldKey.allCases, id: \.self) { k in
                        Text(k == .space ? L("Leertaste") : k.symbol).tag(k)
                    }
                }
            } else {
                ShortcutEditor(shortcut: $button.shortcut)
            }
        }
        .navigationTitle(button.title)
    }
}
