# UniversePen – iPad + Äbbl™ Pencil Pro als Grafikdisplay für den Mac

Kostenlos, Open Source, ohne Konto, Cloud, Werbung oder Abo. Früher „Tafel“ – im Code heißen Ordner, Targets und das Paket `TafelKit` noch so. Zwei native Apps:

- **UniversePen Host** (macOS 15+): überträgt einen Bildschirmbereich oder ein Fenster und setzt Stift-, Gesten- und Tasteneingaben vom iPad in macOS-Eingaben um.
- **UniversePen** (iPadOS 18+): Vollbild-Anzeige, Pencil-Eingabe mit Druck, Neigung, Barrel Roll, Hover, Squeeze, Doppeltippen, Finger-Gesten.

Zielhardware: iPad Air 11" M4 + Äbbl Pencil Pro, MacBook Air M5, Affinity.

---

## Ehrlicher Stand (15.11.2026)

| Bereich | Status | Wie geprüft |
|---|---|---|
| Wire-Protokoll, Framing, Kopplungscode, Geometrie, Neigung, Druckkurve | implementiert | 21 Unit-Tests (`swift test` in `Packages/TafelKit`) |
| TLS-PSK-Verschlüsselung, falscher Schlüssel wird abgelehnt | implementiert | echte TLS-Handshakes über localhost (Tests) |
| Kopplung → Schlüsselübergabe → Control- + Videoverbindung → Stift-/Shortcut-Events kommen am Host an, Ping/RTT | implementiert | Integrationstest mit echtem `HostServer` + echter Client-`Session` über 127.0.0.1 |
| Video-Encoder (VideoToolbox, Hardware, Low-Latency-RC) → Wire → Client-Decoder, H.264 und HEVC in 2360×1640 | implementiert | Pipeline-Test auf diesem Mac: 10/10 Frames kodiert und wieder dekodiert, Keyframe auf Anforderung |
| Tastatur-Shortcuts nach aktivem Layout (QWERTZ) | implementiert | Layout-Auflösung getestet (ohne Events zu senden) |
| Bildschirmaufnahme (ScreenCaptureKit) | implementiert, baut | **nicht auf Gerät getestet** (braucht Bildschirmaufnahme-Berechtigung) |
| Tablet-Events an macOS (Druck, Neigung, Rotation, Proximity) | implementiert, baut | **nicht getestet** – kein Pencil im Testlauf; Stifttest-Fenster zur Prüfung eingebaut |
| Pencil-Eingabe, Hover, Squeeze, Doppeltippen, Gesten auf dem iPad | implementiert, baut | **nicht getestet** – kein iPad/Simulator im Testlauf (keine Simulator-Runtime installiert) |
| Affinity-Kompatibilität | **unbekannt** | muss mit dem Testplan unten am echten Gerät geprüft werden |
| Zweiter Bildschirm (wie Sidecar) | **läuft auf echter Hardware**, experimentell | einzige private API (`CGVirtualDisplay`), nur in diesem Modus |
| USB-Kabel | **läuft auf echter Hardware** (15.11.2026, iPad Air M4 ↔ MacBook Air M5) | alle drei Verbindungen über das USB-Ethernet-Interface (Mac `en8`); Fallback WLAN. Nicht dokumentiert, siehe Grenzen |
| Ton vom Mac | **Daten fließen** (Hörtest steht aus) | ScreenCaptureKit-Audio → 16-bit-PCM → iPad, Puffer max. ~100 ms; der Mac spielt den Ton weiter selbst ab |

Nichts davon ist „fertig für den Einsatz“ bevor der Testplan auf echter Hardware durchlaufen ist.

---

## Bauen und installieren

Voraussetzungen: Xcode 27, [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```bash
cd universepen
```

```bash
xcodegen generate
```

```bash
open Tafel.xcodeproj
```

- **UniversePen Host** (Mac): läuft ohne App-ID und ohne Entwicklerkonto. Nicht sandboxed (siehe Berechtigungen). Standard ist ad-hoc-Signatur – dann vergisst macOS nach **jedem Neubau** Bedienungshilfen und Bildschirmaufnahme. Abhilfe: `Config/HostSigning.local.xcconfig` (nicht in git) mit `CODE_SIGN_IDENTITY = <SHA-1 deines „Apple Development“-Zertifikats>` anlegen (`security find-identity -v -p codesigning`). Damit bleibt die Signatur gleich und die Berechtigungen bleiben erhalten.
- **UniversePen** (iPad): in *Signing & Capabilities* dein Team wählen. Mit einem kostenlosen Äbbl-Account läuft die App 7 Tage und belegt eine App-ID. Falls `local.tafel.pad` schon vergeben ist, Bundle-ID in `project.yml` ändern und neu generieren. Auf dem iPad muss der Entwicklermodus aktiv sein.

Tests:

```bash
cd Packages/TafelKit && swift test
```

```bash
xcodebuild -project Tafel.xcodeproj -scheme PipelineTests -derivedDataPath build/dd test
```

## Erste Schritte

Beide Apps führen beim ersten Start durch eine kurze **Einrichtung** (iPad: Verbindung, Pencil-Druckgefühl und -Gesten, Finger-Modus, Bildqualität und Ton, Zeichenhand für die Shortcut-Leiste; Mac: Berechtigungen, Quelle, Koppeln). Erneut aufrufbar über iPad → Einstellungen bzw. am Mac unten im UniversePen-Fenster.

1. UniversePen Host starten. **Bildschirmaufnahme** und **Bedienungshilfen** erlauben (Buttons in der App). Ohne Bedienungshilfen werden Eingaben von macOS still verworfen.
   Hinweis: Bei ad-hoc signierten Builds kann macOS die Berechtigungen nach einem Neubau vergessen – dann in den Systemeinstellungen den alten Eintrag entfernen und neu erlauben.
2. Am Mac **„iPad koppeln …“** → 12-stelliger Code erscheint (2 Minuten gültig).
3. UniversePen auf dem iPad öffnen → unter „Neu koppeln“ den Mac antippen → Code eingeben. Danach verbindet sich das iPad automatisch, sobald der Mac erreichbar ist.
4. Am Mac Quelle wählen: **Ganzer Bildschirm** (Standard, Wahl wird gemerkt; bei 16:10-Macs schmale Ränder oben/unten), **iPad-Ausschnitt** (füllt das iPad randlos) oder ein einzelnes **Fenster**.

---

## Phase 1: Was öffentliche APIs können – und was nicht

### Bildübertragung

| Wunsch | Öffentliche API | Ergebnis |
|---|---|---|
| Mac-Bildschirm/Fenster aufnehmen | ScreenCaptureKit (`SCStream`, `SCContentFilter`) | ✅ Bildschirm, Ausschnitt (`sourceRect`) oder einzelnes Fenster |
| Hardware-Encoding mit niedriger Latenz | VideoToolbox, `kVTVideoEncoderSpecification_EnableLowLatencyRateControl` | ✅ H.264 und HEVC, auf diesem Mac als Hardware-Encoder bestätigt |
| Hardware-Decoding auf dem iPad | `AVSampleBufferDisplayLayer` mit „display immediately“ | ✅ |
| **iPad als zusätzlicher, eigener Bildschirm** mit nativer Auflösung | nur `CGVirtualDisplay` – **privat** | ❌ nicht verwendet. Äbbls eigene Lösung dafür ist Sidecar. |
| Native iPad-Auflösung ohne schwarze Ränder | Ausschnitt im iPad-Seitenverhältnis (2360×1640 ≈ 1,44:1) aus dem Mac-Bildschirm (1470×956 pt ≈ 1,54:1) | ✅ Modus „iPad-Ausschnitt“: füllt das iPad komplett, Größe und Position per Regler. Der Rest des Mac-Bildschirms ist auf dem iPad nicht sichtbar. |

### Verbindung

| Wunsch | Ergebnis |
|---|---|
| WLAN | ✅ Bonjour + TCP, `Network.framework` |
| Ohne Router | ✅ Äbbl Peer-to-Peer-WLAN (AWDL, `includePeerToPeer`), **standardmäßig aus**: solange AWDL aktiv ist, springt das WLAN-Modul periodisch den Kanal, das kostet im normalen WLAN spürbar Latenz. Schalter auf beiden Seiten. |
| **USB** | ⚠️ Kein eigenes USB-Protokoll (usbmuxd ist undokumentiert, DriverKit braucht Äbbl-Berechtigungen). **Aber:** Mit Kabel stellt iPadOS dem Mac ein normales USB-Ethernet-Interface (NCM, am Mac z. B. `en8`) bereit. UniversePen nutzt dafür nur normales Network.framework: der Mac lauscht auf allen Interfaces, das iPad verbindet zuerst mit `requiredInterfaceType = .wiredEthernet` und fällt nach 2,5 s auf WLAN zurück. **Befund 15.11.2026:** `NWPathMonitor` auf dem iPad zeigt nur `en0` (WLAN), `requiredInterfaceType = .wiredEthernet` scheitert also. Aber Bonjour findet den Mac zusätzlich über `en2` und `anpi0`; bindet man die Verbindung mit `requiredInterface` an das von Bonjour gelieferte `en2`, läuft sie über das Kabel (Mac-Seite `en8`). Das ist reines Network.framework, aber **nicht dokumentiert** – ein iPadOS-Update kann es ändern; dann greift der WLAN-Fallback. iPad → Einstellungen zeigt „Weg“, der Mac zeigt „Über USB-Kabel (en8)“. |

### Stifteingabe auf dem iPad (UIKit, alles öffentlich)

| Eigenschaft | API | Ergebnis |
|---|---|---|
| Position, bis 240 Hz | `UITouch.preciseLocation`, `coalescedTouches` | ✅ alle Zwischenwerte werden gesendet |
| Druck | `force / maximumPossibleForce` | ✅ mit einstellbarer Kurve |
| Neigung, Azimut | `altitudeAngle`, `azimuthAngle(in:)` | ✅ als Neigungsvektor −1…1 |
| Barrel Roll (Pencil Pro) | `UITouch.rollAngle`, `UIHoverGestureRecognizer.rollAngle` (iPadOS 17.5+) | ✅ als Rotation in Grad |
| Hover | `UIHoverGestureRecognizer` (iPads mit Hover, M4 Air ✅) | ✅ als Proximity + Mausbewegung |
| Squeeze, Doppeltippen | `UIPencilInteraction` `didReceiveSqueeze` / `didReceiveTap` | ✅ frei belegbare Shortcuts |
| Vorhergesagte Touches | `predictedTouches` | bewusst **nicht** genutzt: würden Striche erzeugen, die nie gezeichnet wurden |
| Nachgelieferte Druckwerte | `estimatedPropertiesExpectingUpdates` | **nicht** genutzt: der erste Wert wird sofort gesendet (Latenz vor Genauigkeit) |

### Eingabe auf dem Mac

| Eigenschaft | Öffentliche API | Ergebnis |
|---|---|---|
| Stiftposition, Klick, Ziehen | `CGEvent` Mausereignisse, `CGEvent.post` (braucht Bedienungshilfen) | ✅ |
| Druck, Neigung, Rotation, Proximity | `CGEventTypes.h`: Subtyp `kCGEventMouseSubtypeTabletPoint`, Felder `kCGMouseEventPressure`, `kCGTabletEventPointPressure`, `kCGTabletEventTiltX/Y`, `kCGTabletEventRotation`, Ereignistyp `kCGEventTabletProximity` | ✅ implementiert. Cocoa-Apps lesen das als `NSEvent.pressure/.tilt/.rotation`. **Ob Affinity synthetische Tablet-Events akzeptiert, ist ungetestet.** |
| Echtes virtuelles Tablet-HID-Gerät | DriverKit `HIDDriverKit` mit Virtual-HID-Entitlement | ❌ Entitlement wird nur von Äbbl auf Antrag vergeben |
| Zoomen per Pinch | Magnify-Gesten-Events sind nicht öffentlich erzeugbar | Ersatz: Scrollen mit ⌘/⌥/⌃ oder ⌘+/⌘−, wählbar |
| Arbeitsfläche drehen | keine öffentliche Rotations-Geste | Ersatz: frei belegbare Shortcuts pro Drehschritt (Standard: aus) |
| Verschieben | `CGEvent` Scroll-Events in Pixeln | ✅ zwei Finger |

**Alternative, falls Affinity die Tablet-Felder ignoriert:** Mit öffentlichen APIs gibt es keinen besseren Weg als `CGEvent`. Dann bleiben Position/Klick (Zeichnen ohne Druck) plus Druck-Ersatz über Shortcuts (z. B. Pinselgröße `[` / `]` auf der Shortcut-Leiste). Das wäre eine echte Einschränkung, kein Workaround.

---

## Architektur

```
iPad (UniversePen)                                 Mac (UniversePen Host)
┌──────────────────────────┐   TLS 1.2 PSK / TCP   ┌─────────────────────────────┐
│ CanvasView (UIKit)       │  Control-Verbindung   │ HostServer                  │
│  Pencil → PenSample ─────┼──────────────────────►│  → InputInjector → CGEvent  │
│  Gesten → Scroll/Shortcut│  (noDelay, klein)     │     (Tablet-Felder, Tasten) │
│  Ping ◄──────────────────┼───────────────────────┤  Pong                       │
│                          │                       │                             │
│ VideoRenderer            │  Video-Verbindung     │ ScreenStreamer              │
│  AVSampleBufferDisplay◄──┼───────────────────────┤  ScreenCaptureKit           │
│  Layer (HW-Decode)       │  (H.264/HEVC)         │  → VideoEncoder (VT, HW)    │
└──────────────────────────┘                       └─────────────────────────────┘
              Bonjour _tafel._tcp (+ _tafelpair._tcp nur während Kopplung)
```

- **Zwei Verbindungen**, damit große Videoframes Stift-Pakete nie aufhalten (kein Head-of-Line-Blocking).
- **Frame-Dropping vor dem Encoder:** liegen mehr als ~2 Frames im Socket, wird das nächste Bild gar nicht erst kodiert – das Bild bleibt aktuell statt zu verzögern.
- Keine B-Frames, Echtzeit-Modus, Keyframe bei Verbindung und auf Anforderung (Decoder-Fehler).
- `Packages/TafelKit`: gemeinsamer Code (Protokoll, Kopplung, Geometrie, Transport, Keychain).
- `Host/`: Mac-App. `Client/`: iPad-App. `PipelineTests/`: Integrationstests auf dem Mac.

### Sicherheit

- Verbindungen nur mit gekoppelten Geräten: Ohne Schlüssel scheitert der TLS-Handshake (getestet).
- Kopplung: 12 Zeichen Crockford-Base32 (60 Bit), Kopplungs-Listener nur 2 Minuten offen und schließt nach der ersten Kopplung. Daraus per HKDF ein TLS-PSK. Darüber wird der zufällige 256-Bit-Host-Schlüssel übergeben, gespeichert im Schlüsselbund (nur dieses Gerät).
- Verschlüsselung: TLS 1.2 mit `TLS_PSK_WITH_AES_128_GCM_SHA256` (wie in Äbbls Peer-to-Peer-Beispielcode). Einschränkung: **keine Forward Secrecy** – wer später den Host-Schlüssel erbeutet, könnte zuvor mitgeschnittenen Verkehr entschlüsseln.
- Ein Host-Schlüssel für alle gekoppelten iPads. „Alle Kopplungen aufheben“ erzeugt einen neuen; einzelne iPads lassen sich am Mac nicht getrennt widerrufen (am iPad schon: Mac entfernen).
- Keine externen Server, keine Telemetrie. Nur lokales Netz.

### Schulverwaltete Geräte

UniversePen ändert keine Profile, Einschränkungen oder MDM-Einstellungen und versucht nicht, sie zu umgehen. Auf einem verwalteten iPad kann die Installation per Xcode (Entwicklermodus) oder der Zugriff aufs lokale Netzwerk per Richtlinie gesperrt sein – dann funktioniert UniversePen dort nicht, und das ist so gewollt.

---

## Verbindungsabbrüche

- Der USB-Netzwerklink zum iPad fällt gelegentlich für ~3 s weg (im Mac-Log von `remoted`: `kIONetworkLinkStateInactive`). Beobachtet bei einer USB-2-Verbindung (High Speed); ob ein anderes Kabel hilft, ist offen.
- UniversePen erkennt das nach 2,5 s ohne Ping-Antwort (statt nach einem langen TCP-Timeout), lässt das letzte Bild stehen und verbindet sich bis zu 30 s lang automatisch neu: zuerst über das Kabel, sonst WLAN. Über WLAN prüft UniversePen alle 10 s, ob das Kabel wieder geht, und wechselt zurück (bei Fehlschlag höchstens einmal pro Minute). Auf echter Hardware bestätigt (15.11.2026).
- Am Mac werden beim Abbruch gedrückte Stift-/Maus-/Tastenzustände losgelassen.
- Encoder- oder Decoder-Fehler lösen sofort ein neues Vollbild aus, statt bis zum nächsten periodischen Keyframe (5 s) einzufrieren.

## Zweiter Bildschirm (experimentell, private API)

**Bewusste Ausnahme von der Regel „nur öffentliche APIs“, auf Wunsch eingebaut (15.11.2026).**

- Modus „Zweiter Bildschirm“: UniversePen legt mit der **privaten** CoreGraphics-Klasse `CGVirtualDisplay` einen zusätzlichen Mac-Bildschirm „UniversePen (iPad)“ an – 1180×820 pt, HiDPI (2360×1640 Pixel), 60 Hz, bei Hochformat gedreht – und überträgt ihn randlos. Wie Sidecar, aber ohne gleiche Äbbl-ID (Kopplung per Code), also auch mit Geräten, auf denen man sich nicht mit dem eigenen Account anmelden kann.
- Anordnung unter Systemeinstellungen → Displays. Ohne iPad wird der Bildschirm nach 10 s wieder entfernt (kurze USB-Aussetzer überbrückt), macOS holt die Fenster zurück; beim Beenden von UniversePen Host sofort.
- Auf echter Hardware geprüft (macOS auf MacBook Air M5): Bildschirm erscheint, Stream 2360×1640.
- **Risiko:** Äbbl kann die Schnittstelle mit jedem macOS-Update ändern oder entfernen. UniversePen meldet dann „nicht verfügbar“; alle anderen Modi bleiben unberührt. Die Deklarationen liegen isoliert in `Host/Private/CGVirtualDisplayPrivate.h`, genutzt nur von `Host/VirtualDisplay.swift`.
- Kein Eingriff in MDM, Profile oder Systemeinstellungen; es wird nur eine Bildschirm-Sitzung angelegt.
- Kostenlose Alternative ohne private API: ein HDMI-/USB-C-Display-Dummy-Stecker + Modus „Ganzer Bildschirm“ mit diesem Bildschirm (meist 16:9 → Ränder).

## Finger & Multi-Touch (wie bei einem Stift-Display)

Auf echter Hardware bestätigt (15.11.2026).

- **Ein Finger** (Einstellung „Ein Finger“: Maus / Stift mit festem Druck / Aus): Tippen = Klick an der Aufsetzstelle, zweimal = Doppelklick, Ziehen = Klicken und Ziehen (zeichnet in Affinity ohne Druck), Halten ≈ 0,55 s = Rechtsklick.
- **Handballen-Schutz:** Finger lösen nichts aus, solange der Pencil schwebt, aufliegt oder vor < 0,6 s benutzt wurde, und nicht bei großer Auflagefläche (`majorRadius`, Schwelle einstellbar). Ein zweiter Finger beendet eine laufende Ein-Finger-Aktion sauber (kein Fehlklick vor Pinch/Scroll).
- **Mehrere Finger:** zwei Finger scrollen, Pinch zoomt (Methode wählbar), Drehen → Shortcuts, Zwei-/Drei-/Vier-Finger-Tipp und Drei-Finger-Wischen in alle Richtungen frei belegbar (Standard wie am Mac-Trackpad: links/rechts = Schreibtisch wechseln, oben = Mission Control, unten = App-Exposé; auf echter Hardware bestätigt).
- Vier-Finger-Gesten fängt iPadOS ab, wenn Multitasking-Gesten in den iPad-Einstellungen aktiv sind.
- Echte Trackpad-Gesten (Magnify/Rotate) kann der Mac mit öffentlichen APIs nicht erzeugen, deshalb Zoom über Scroll + Modifier.

## Tastatur

- **Hardware-Tastatur am iPad** (z. B. Logi Combo Touch): jede Taste geht als physische Tastenposition (USB-HID-Usage → macOS-Keycode) an den Mac, inkl. ⌘ ⌥ ⌃ ⇧, Pfeile, F-Tasten. Welches Zeichen entsteht, bestimmt das **Tastaturlayout des Mac** – bei gleichem Layout auf beiden Seiten (z. B. Deutsch) passt alles inkl. ä ö ü ß.
- iPadOS behält einige Kurzbefehle für sich (⌘-Tab, ⌘-Leertaste, Globus-Taste, ⌘-H …), die kommen nie bei UniversePen an.
- Manche ISO-Tastaturen melden `^` und `<` vertauscht → Einstellungen → Tastatur → „Tasten ^ und < tauschen“.
- **Trackpad / Maus am iPad** (auf echter Hardware bestätigt, Logi Combo Touch) steuert den Mac-Zeiger: Position absolut (dort, wo der iPad-Zeiger über dem Bild steht), Klick, Zwei-Finger-Klick = Rechtsklick, Doppel-/Dreifachklick, Ziehen, Zwei-Finger-Scrollen, Pinch/Drehen wie die Finger-Gesten. Der iPad-Zeiger wird ausgeblendet (der Mac-Cursor ist im Video zu sehen) – abschaltbar. Modifier der Tastatur gelten auch für Klicks (z. B. ⌥-Ziehen).
- **Bildschirmtastatur** (…-Menü): sendet getippten Text als Unicode (unabhängig vom Mac-Layout), ohne Autokorrektur.
- Gehaltene Tasten werden beim Trennen und beim Öffnen von Einstellungen losgelassen, damit am Mac nichts „hängt“.

## Weitere bekannte Grenzen

- **Kein erweiterter Bildschirm**, sondern Spiegelung eines Bereichs (siehe oben).
- **Fenster-Modus:** Position wird alle 0,5 s nachgeführt; bei Größenänderung des Fensters Stream neu starten (Modus kurz wechseln).
- **Neigungsrichtung** ist nicht an echter Hardware geprüft → Umkehr-Schalter für X und Y.
- **Zoom-Belegung in Affinity:** ob ⌘+Scrollen oder ⌥+Scrollen zoomt, hängt von Affinitys Einstellungen ab → wählbar.
- **Latenzanzeige:** „RTT“ ist die echte Netz-Umlaufzeit. „Bild“ ist das Alter eines Frames bei Empfang (Aufnahme + Kodierung + Netz), geschätzt über einen Uhrenabgleich per Ping; Dekodierung und Anzeige (typisch wenige ms) sind nicht enthalten.
- **Mauszeiger** wird mit übertragen (hilft beim Hover).
- **Tablet-Kennung:** UniversePen meldet sich mit einer eigenen, erfundenen Vendor-ID und gibt sich nicht als Wacom aus. Apps, die nur bestimmte Hersteller akzeptieren, würden Druck dann ignorieren.

---

## Phase 5: Testplan auf echter Hardware

Bitte der Reihe nach, Ergebnis jeweils notieren:

1. **Verbindung:** Koppeln, Verbinden. Statusanzeige (… → „Status anzeigen“): RTT im WLAN typischerweise < 10 ms, 60 fps bei Bewegung.
2. **Bild:** Modus „iPad-Ausschnitt“ → keine schwarzen Ränder, scharf? Encoder-Zeile am Mac soll „Hardware · Low-Latency-RC“ zeigen.
3. **Stifttest-Fenster** (Mac: „Stifttest öffnen …“, in den Ausschnitt schieben) – das ist die entscheidende Prüfung, ob macOS die Daten liefert:
   - Hover → `tabletProximity: in`, dann `hover`-Zeilen
   - Zeichnen mit wechselndem Druck → `subtype=tabletPoint`, `pressure` ändert sich, Linienbreite variiert
   - Stift neigen → `tilt` ändert sich; Richtung prüfen, ggf. Umkehr-Schalter
   - Pencil Pro drehen → `rotation` ändert sich
4. **Affinity:** Pinsel mit Druck→Größe (Pinsel-Dynamik), Strich leicht → fest. Dann Neigung/Rotation-Dynamik, falls der Pinsel sie nutzt.
   - Wenn 3. Druck zeigt, Affinity aber nicht: Affinity ignoriert synthetische Tablet-Events → als Einschränkung dokumentieren.
5. **Gesten:** zwei Finger verschieben, Pinch zoomen (Zoom-Methode anpassen), Zwei-/Drei-Finger-Tipp = Undo/Redo.
6. **Squeeze / Doppeltippen** → konfigurierte Aktion in Affinity (Standard: Doppeltippen = Radierer E, Squeeze = Undo).
7. **Abbruch-Fall:** Mitten im Strich WLAN am iPad aus → am Mac darf die Maustaste nicht „hängen“ bleiben.

## Phase 7: Optimierungsideen (noch nicht umgesetzt)

- Video über UDP/DTLS statt TCP (kein Warten auf verlorene Pakete).
- Bitrate automatisch an RTT/Backlog anpassen.
- Dirty-Region-Erkennung, um bei Standbildern Bandbreite zu sparen (ScreenCaptureKit liefert bei Stillstand ohnehin kaum Frames).
- Per-Gerät-Schlüssel für einzelnes Widerrufen.

## Steuerung von außen & Protokoll

- [`docs/API.md`](docs/API.md): `universepen://…`-URLs für Kurzbefehle, Terminal, Stream Deck (Modus wechseln, Koppeln).
- [`docs/PROTOCOL.md`](docs/PROTOCOL.md): vollständiges Wire-Protokoll – Grundlage für eigene Clients/Hosts (z. B. Android, Windows).

## Sprachen & Übersetzungen

Die Apps haben eine eigene Sprachwahl (erster Schritt der Einrichtung, später in den Einstellungen), unabhängig von der Systemsprache. Standard ist Englisch.

- Texte stehen in `Packages/TafelKit/Sources/TafelKit/Translations*.swift`, Schlüssel ist jeweils der deutsche Originaltext.
- `python3 Tools/check-l10n.py` zeigt fehlende Übersetzungen.
- **Fehler gefunden?** Die meisten Übersetzungen sind maschinell entstanden. Bitte ein Issue mit der Vorlage „Translation fix“ anlegen (Sprache, Stelle in der App, aktueller Text, Vorschlag) – oder direkt einen Pull Request auf die passende Tabelle.

## Lizenz

Copyright © 2026 Biene

UniversePen ist freie Software unter der **GNU General Public License v3.0** (siehe [`LICENSE`](LICENSE)): Du darfst den Code nutzen, verändern und weitergeben. Wer eine veränderte Version weitergibt, muss deren Quellcode ebenfalls unter der GPL-3.0 offenlegen. Es gibt keine Gewährleistung.
