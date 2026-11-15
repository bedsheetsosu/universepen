# UniversePen – iPad + Äbbl™ Pencil Pro as a pen display for the Mac

Free and open source. No account, no cloud, no ads, no subscription. Formerly called "Tafel": folders, targets and the `TafelKit` package still use that name in the code. Two native apps:

- **UniversePen Host** (macOS 15+): streams a screen region or a window and turns pen, gesture and keyboard input from the iPad into macOS input.
- **UniversePen** (iPadOS 18+): full-screen view, Pencil input with pressure, tilt, barrel roll, hover, squeeze, double-tap, finger gestures.

Target hardware: iPad Air 11" M4 + Äbbl Pencil Pro, MacBook Air M5, Affinity.

---

## Honest status (2026-11-15)

| Area | Status | How it was checked |
|---|---|---|
| Wire protocol, framing, pairing code, geometry, tilt, pressure curve | implemented | 21 unit tests (`swift test` in `Packages/TafelKit`) |
| TLS-PSK encryption, wrong key is rejected | implemented | real TLS handshakes over localhost (tests) |
| Pairing → key handover → control + video connection → pen/shortcut events reach the host, ping/RTT | implemented | integration test with a real `HostServer` + real client `Session` over 127.0.0.1 |
| Video encoder (VideoToolbox, hardware, low-latency rate control) → wire → client decoder, H.264 and HEVC at 2360×1640 | implemented | pipeline test on this Mac: 10/10 frames encoded and decoded again, keyframe on request |
| Keyboard shortcuts following the active layout (QWERTZ) | implemented | layout resolution tested (without sending events) |
| Screen capture (ScreenCaptureKit) | **runs on real hardware** (2026-11-15) | streaming to the iPad in daily use, e.g. second screen at 2360×1640, HEVC, 60 fps (reported by the developer API) |
| Tablet events to macOS (pressure, tilt, rotation, proximity) | **runs on real hardware** (2026-11-15) | Affinity reads pressure, tilt and rotation from the synthetic tablet events (see the Affinity row) |
| Pencil input, hover, squeeze, double-tap, gestures on the iPad | **runs on real hardware** (2026-11-15) | pressure, tilt, barrel roll, squeeze, double-tap and pinch/rotate checked live via the developer API; hover confirmed in Affinity |
| Affinity compatibility | **works on real hardware** (2026-11-15) | in regular use: pressure → stroke width, tilt and barrel roll, hover brush preview, gestures and shortcuts (zoom, pan, undo, squeeze/double-tap) |
| Pressure curve editor & per-app shortcut bar | **runs on real hardware** (2026-11-15) | freely drawable curve with live test, smoothing, hold keys, the bar follows the Mac app |
| Instant ink, hover dot, time-lapse, tablet mode | implemented, builds (2026-11-15) | **not yet tried on real hardware** |
| Source switching from the iPad, undo scrub, game mode, custom colours / flowing background, pen taps in games (osu!: pointer follows every tap) | **runs on real hardware** (2026-11-15) | confirmed by use |
| Squeeze radial menu, per-app Pencil profiles, Mac menu bar (status, iPad battery, mode) | **runs on real hardware** (2026-11-15) | radial menu with hover + squeeze, Affinity profile switching with the front app, battery shown in the menu bar |
| Second screen (like Sidecar) | **runs on real hardware**, experimental | the only private API (`CGVirtualDisplay`), used only in this mode |
| USB cable | **runs on real hardware** (2026-11-15, iPad Air M4 ↔ MacBook Air M5) | all three connections over the USB Ethernet interface (Mac `en8`); falls back to Wi-Fi. Undocumented, see limits |
| Sound from the Mac | **data flows** (listening test pending) | ScreenCaptureKit audio → 16-bit PCM → iPad, buffer max. ~100 ms; the Mac keeps playing the sound itself |

Confirmed so far on one setup (iPad Air M4, Pencil Pro, MacBook Air M5, Affinity). Other apps, devices and macOS versions are untested.

---

## Build and install

Requirements: Xcode 27, [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```bash
cd universepen
```

```bash
xcodegen generate
```

```bash
open Tafel.xcodeproj
```

- **UniversePen Host** (Mac, bundle ID `local.universepen.host`; up to 0.1.1 it was "Tafel Host", `local.tafel.host` – its settings are taken over on first launch, permissions have to be granted again): runs without an App ID and without a developer account. Not sandboxed (see permissions). The default is ad-hoc signing – then macOS forgets Accessibility and Screen Recording after **every rebuild**. Fix: create `Config/HostSigning.local.xcconfig` (not in git) with `CODE_SIGN_IDENTITY = <SHA-1 of your "Apple Development" certificate>` (`security find-identity -v -p codesigning`). The signature then stays the same and the permissions are kept.
- **UniversePen** (iPad): pick your team under *Signing & Capabilities*. With a free Äbbl account the app runs for 7 days and uses up one App ID. If `local.tafel.pad` is already taken, change the bundle ID in `project.yml` and regenerate. Developer Mode must be on on the iPad.

### Without a Mac: sideload the IPA

Every [release](https://github.com/bedsheetsosu/universepen/releases) has an **unsigned** `UniversePen-<version>-unsigned.ipa`. iPadOS only runs apps that are signed for your device, so a sideloading tool has to sign it with your own Äbbl account first – e.g. SideStore, AltStore or Sideloadly (the last two also run on Windows). With a free account the app runs for 7 days at a time and the tool usually changes the bundle ID; both are fine.

For now the iPad still needs the Mac app (UniversePen Host) on the other side – there is no Windows host yet. The IPA just means you don't need Xcode for the iPad part.

Tests:

```bash
cd Packages/TafelKit && swift test
```

```bash
xcodebuild -project Tafel.xcodeproj -scheme PipelineTests -derivedDataPath build/dd test
```

## Getting started

On first launch both apps walk you through a short **setup** (iPad: connection, Pencil pressure feel and gestures, finger mode, image quality and sound, drawing hand for the shortcut bar; Mac: permissions, source, pairing). You can open it again from iPad → Settings, or at the bottom of the UniversePen window on the Mac.

1. Start UniversePen Host. Allow **Screen Recording** and **Accessibility** (buttons in the app). Without Accessibility, macOS silently drops all input.
   Note: with ad-hoc signed builds macOS may forget the permissions after a rebuild – then remove the old entry in System Settings and allow it again.
2. On the Mac, click **"Pair iPad …"** → a 12-character code appears (valid for 2 minutes).
3. Open UniversePen on the iPad → tap the Mac under "Pair new" → enter the code. From then on the iPad connects automatically whenever the Mac is reachable.
4. Pick a source on the Mac: **Full display** (default, the choice is remembered; 16:10 Macs get thin bars at the top and bottom), **iPad region** (fills the iPad edge to edge), a single **Window**, or the experimental **Second screen**.

---

## Phase 1: What public APIs can do – and what they can't

### Video

| Goal | Public API | Result |
|---|---|---|
| Capture the Mac screen/a window | ScreenCaptureKit (`SCStream`, `SCContentFilter`) | ✅ screen, region (`sourceRect`) or a single window |
| Low-latency hardware encoding | VideoToolbox, `kVTVideoEncoderSpecification_EnableLowLatencyRateControl` | ✅ H.264 and HEVC, confirmed as hardware encoder on this Mac |
| Hardware decoding on the iPad | `AVSampleBufferDisplayLayer` with "display immediately" | ✅ |
| **iPad as an additional, separate display** at native resolution | only `CGVirtualDisplay` – **private** | ⚠️ not available through public APIs. Äbbl's own solution is Sidecar. UniversePen offers it as a deliberate, experimental exception (see "Second screen"). |
| Native iPad resolution without black bars | region in the iPad aspect ratio (2360×1640 ≈ 1.44:1) taken from the Mac screen (1470×956 pt ≈ 1.54:1) | ✅ "iPad region" mode: fills the iPad completely, size and position via sliders. The rest of the Mac screen is not visible on the iPad. |

### Connection

| Goal | Result |
|---|---|
| Wi-Fi | ✅ Bonjour + TCP, `Network.framework` |
| Without a router | ✅ Äbbl peer-to-peer Wi-Fi (AWDL, `includePeerToPeer`), **off by default**: while AWDL is active the Wi-Fi radio hops channels periodically, which costs noticeable latency on normal Wi-Fi. Switch on both sides. |
| **USB** | ⚠️ No custom USB protocol (usbmuxd is undocumented, DriverKit needs Äbbl entitlements). **But:** with a cable, iPadOS gives the Mac a normal USB Ethernet interface (NCM, e.g. `en8` on the Mac). UniversePen only uses plain Network.framework for it: the Mac listens on all interfaces, the iPad first connects with `requiredInterfaceType = .wiredEthernet` and falls back to Wi-Fi after 2.5 s. **Finding 2026-11-15:** `NWPathMonitor` on the iPad only shows `en0` (Wi-Fi), so `requiredInterfaceType = .wiredEthernet` fails. But Bonjour also finds the Mac via `en2` and `anpi0`; pinning the connection with `requiredInterface` to the `en2` that Bonjour returns makes it run over the cable (Mac side `en8`). That is plain Network.framework, but **undocumented** – an iPadOS update may change it; then the Wi-Fi fallback kicks in. iPad → Settings shows "Path", the Mac shows "Via USB cable (en8)". |

### Pen input on the iPad (UIKit, all public)

| Property | API | Result |
|---|---|---|
| Position, up to 240 Hz | `UITouch.preciseLocation`, `coalescedTouches` | ✅ all intermediate samples are sent |
| Pressure | `force / maximumPossibleForce` | ✅ with an adjustable curve |
| Tilt, azimuth | `altitudeAngle`, `azimuthAngle(in:)` | ✅ as a tilt vector −1…1 |
| Barrel roll (Pencil Pro) | `UITouch.rollAngle`, `UIHoverGestureRecognizer.rollAngle` (iPadOS 17.5+) | ✅ as rotation in degrees |
| Hover | `UIHoverGestureRecognizer` (iPads with hover, M4 Air ✅) | ✅ as proximity + mouse movement |
| Squeeze, double-tap | `UIPencilInteraction` `didReceiveSqueeze` / `didReceiveTap` | ✅ freely assignable shortcuts |
| Predicted touches | `predictedTouches` | deliberately **not** used: they would create strokes that were never drawn |
| Late pressure updates | `estimatedPropertiesExpectingUpdates` | **not** used: the first value is sent right away (latency before accuracy) |

### Input on the Mac

| Property | Public API | Result |
|---|---|---|
| Pen position, click, drag | `CGEvent` mouse events, `CGEvent.post` (needs Accessibility) | ✅ |
| Pressure, tilt, rotation, proximity | `CGEventTypes.h`: subtype `kCGEventMouseSubtypeTabletPoint`, fields `kCGMouseEventPressure`, `kCGTabletEventPointPressure`, `kCGTabletEventTiltX/Y`, `kCGTabletEventRotation`, event type `kCGEventTabletProximity` | ✅ implemented. Cocoa apps read this as `NSEvent.pressure/.tilt/.rotation`. **Affinity accepts them** (pressure, tilt, rotation, confirmed 2026-11-15). |
| Real virtual tablet HID device | DriverKit `HIDDriverKit` with the virtual HID entitlement | ❌ Äbbl only grants the entitlement on request |
| Pinch to zoom | magnify gesture events can't be created with public APIs | substitute: scrolling with ⌘/⌥/⌃ or ⌘+/⌘−, selectable |
| Rotate the canvas | no public rotation gesture | substitute: freely assignable shortcuts per rotation step (default: off) |
| Pan | `CGEvent` scroll events in pixels | ✅ two fingers |

**Fallback if Affinity ignores the tablet fields:** with public APIs there is no better way than `CGEvent`. What's left is position/click (drawing without pressure) plus pressure substitutes via shortcuts (e.g. brush size `[` / `]` on the shortcut bar). That would be a real limitation, not a workaround.

---

## Architecture

```
iPad (UniversePen)                                 Mac (UniversePen Host)
┌──────────────────────────┐   TLS 1.2 PSK / TCP   ┌─────────────────────────────┐
│ CanvasView (UIKit)       │  control connection   │ HostServer                  │
│  Pencil → PenSample ─────┼──────────────────────►│  → InputInjector → CGEvent  │
│  gestures → scroll/keys  │  (noDelay, small)     │     (tablet fields, keys)   │
│  ping ◄──────────────────┼───────────────────────┤  pong                       │
│                          │                       │                             │
│ VideoRenderer            │  video connection     │ ScreenStreamer              │
│  AVSampleBufferDisplay◄──┼───────────────────────┤  ScreenCaptureKit           │
│  Layer (HW decode)       │  (H.264/HEVC)         │  → VideoEncoder (VT, HW)    │
└──────────────────────────┘                       └─────────────────────────────┘
              Bonjour _tafel._tcp (+ _tafelpair._tcp only while pairing)
```

- **Two connections**, so large video frames never hold up pen packets (no head-of-line blocking).
- **Frame dropping before the encoder:** if more than ~2 frames are queued in the socket, the next frame isn't encoded at all – the image stays current instead of lagging.
- No B-frames, real-time mode, keyframe on connect and on request (decoder errors).
- `Packages/TafelKit`: shared code (protocol, pairing, geometry, transport, keychain).
- `Host/`: Mac app. `Client/`: iPad app. `PipelineTests/`: integration tests on the Mac.

### Security

- Connections only with paired devices: without the key the TLS handshake fails (tested).
- Pairing: 12 characters of Crockford Base32 (60 bits); the pairing listener is open for only 2 minutes and closes after the first pairing. A TLS PSK is derived from it via HKDF. Over that, the random 256-bit host key is handed over and stored in the keychain (this device only).
- Encryption: TLS 1.2 with `TLS_PSK_WITH_AES_128_GCM_SHA256` (as in Äbbl's peer-to-peer sample code). Limitation: **no forward secrecy** – anyone who later gets hold of the host key could decrypt previously recorded traffic.
- One host key for all paired iPads. "Unpair all" creates a new one; individual iPads can't be revoked separately on the Mac (they can on the iPad: remove the Mac).
- No external servers, no telemetry. Local network only.

### School-managed devices

UniversePen does not change profiles, restrictions or MDM settings and does not try to get around them. On a managed iPad, installing via Xcode (Developer Mode) or local network access may be blocked by policy – then UniversePen won't work there, and that is intended.

---

## Connection drops

- The USB network link to the iPad occasionally drops for ~3 s (in the Mac log from `remoted`: `kIONetworkLinkStateInactive`). Seen on a USB 2 connection (High Speed); whether another cable helps is still open.
- UniversePen detects this after 2.5 s without a ping reply (instead of after a long TCP timeout), keeps the last frame on screen and reconnects automatically for up to 30 s: over the cable first, otherwise Wi-Fi. While on Wi-Fi, UniversePen checks every 10 s whether the cable works again and switches back (after a failure at most once per minute). Confirmed on real hardware (2026-11-15).
- On the Mac, any pressed pen/mouse/key state is released when the connection drops.
- Encoder or decoder errors trigger a new full frame immediately instead of freezing until the next periodic keyframe (5 s).

## Second screen (experimental, private API)

**A deliberate exception to the "public APIs only" rule, added on request (2026-11-15).**

- "Second screen" mode: UniversePen uses the **private** CoreGraphics class `CGVirtualDisplay` to create an additional Mac display "UniversePen (iPad)" – 1180×820 pt, HiDPI (2360×1640 pixels), 60 Hz, rotated in portrait – and streams it edge to edge. Like Sidecar, but without needing the same Äbbl ID (pairing by code), so it also works with devices you can't sign in to with your own account.
- Arrange it under System Settings → Displays. Without the iPad the display is removed after 10 s (short USB dropouts are bridged) and macOS brings the windows back; when UniversePen Host quits, it's removed immediately.
- Checked on real hardware (macOS on MacBook Air M5): the display appears, stream at 2360×1640.
- **Risk:** Äbbl can change or remove this interface with any macOS update. UniversePen then reports "not available"; all other modes are unaffected. The declarations are isolated in `Host/Private/CGVirtualDisplayPrivate.h` and only used by `Host/VirtualDisplay.swift`.
- No changes to MDM, profiles or system settings; it only creates a display session.
- Free alternative without a private API: an HDMI/USB-C display dummy plug + "Full display" mode on that display (usually 16:9 → bars).

## Radial menu, per-app Pencil profiles, menu bar

- **Radial menu:** set squeeze (or double-tap) to "Radial menu". A ring with 2–8 actions appears at the Pencil tip (where it hovers). Hover over an item and squeeze again, or tap it; tap the centre or outside to close. Highlight and pick give a haptic tick on the Pencil Pro. Items: iPad → Settings → Radial menu. While the ring is open, nothing is sent to the Mac.
- **Per-app Pencil profiles:** pressure curve, smoothing, double-tap and squeeze can have their own values per Mac app (iPad → Settings → Pencil → "Settings for"). They switch automatically with the app in front on the Mac, like the per-app shortcut bars.
- **Full Mac resolution (on by default):** with a "more space" second screen or a region, the Mac sends all captured pixels unscaled and the iPad scales them down when showing them – noticeably sharper than scaling on the Mac (confirmed 2026-11-15). Costs more bitrate; iPad → Settings → Image to switch off. The second screen offers five sharp HiDPI steps (1180×820 to 1888×1312 points); the default step is 1:1 with the iPad's pixels and the sharpest.
- **Switch the source from the iPad:** … menu → Source: full display, iPad region, second screen, or a window from the Mac's window list – no trip to the Mac.
- **Undo scrub:** rest two fingers briefly, then drag left (undo) or right (redo), one step per 40 pt (adjustable). A pill shows the count. iPads have no haptic engine for fingers, so the feedback is visual only.
- **Game mode** (e.g. osu!): … menu → "Game mode for <app>". While that app is in front on the Mac: 60 fps, full resolution, ≥ 60 Mbit/s, no adaptive bitrate, no smoothing. The iPad Air's display is 60 Hz, so more than 60 fps isn't possible.
- **Colours:** pick an accent (presets or the system colour wheel) on iPad → Settings → Colours or in the Mac window; it runs through buttons, rings, the radial menu and the bar. "Flowing background" turns the still gradient into a slowly moving mesh whose hues drift (speed adjustable). Only behind menus and setup, never over the streamed picture.
- **Instant ink:** the stroke appears on the iPad right away as a thin trail in the accent colour and fades after about the measured picture delay – when the Mac's real stroke arrives underneath. Hides most of the stream latency while drawing. iPad → Settings → Pencil.
- **Hover dot:** a small ring under the hovering Pencil tip, drawn on the iPad (the Mac cursor in the video lags behind).
- **Time-lapse (Mac):** records the streamed picture as an HEVC time-lapse (10×–120×) to Movies → UniversePen. ScreenCaptureKit only delivers frames when the screen changes, so idle time is skipped. Start/stop in the Mac window or the menu bar; a change of picture size (other source/resolution) closes the file.
- **Tablet mode** (like a screenless pen tablet, e.g. for osu! without a tablet): … menu → "Tablet mode (no picture)". The Mac stops capturing; the iPad turns black with a fine dot grid and corner marks for the active area, which maps absolutely onto the whole selected Mac display. Outside the area the cursor stays at the edge. Move/resize the area with "Adjust active area" (size shown in mm, optionally locked to the Mac display's aspect ratio). Fingers are off in this mode so the hand can rest on the glass.
- **Menu bar (Mac):** connected iPad, path (USB/Wi-Fi), fps and bitrate, iPad battery, source switch, pairing, quit.

## Fingers & multi-touch (like on a pen display)

Confirmed on real hardware (2026-11-15).

- **One finger** (setting "One finger": Mouse / Pen with fixed pressure / Off): tap = click where you touch, tap twice = double-click, drag = click and drag (draws in Affinity without pressure), hold ≈ 0.55 s = right-click.
- **Palm rejection:** fingers do nothing while the Pencil hovers, touches, or was used less than 0.6 s ago, nor with a large contact area (`majorRadius`, adjustable threshold). A second finger cleanly ends a running one-finger action (no stray click before pinch/scroll).
- **Multiple fingers:** two fingers scroll, pinch zooms (method selectable), rotate → shortcuts, two-/three-/four-finger tap and three-finger swipe in all directions are freely assignable (defaults like a Mac trackpad: left/right = switch desktop, up = Mission Control, down = App Exposé; confirmed on real hardware).
- iPadOS intercepts four-finger gestures if multitasking gestures are enabled in the iPad settings.
- The Mac can't create real trackpad gestures (magnify/rotate) with public APIs, so zoom works via scroll + modifier.

## Keyboard

- **Hardware keyboard on the iPad** (e.g. Logi Combo Touch): every key is sent to the Mac as a physical key position (USB HID usage → macOS keycode), including ⌘ ⌥ ⌃ ⇧, arrows, F keys. Which character comes out is decided by the **Mac's keyboard layout** – with the same layout on both sides (e.g. German) everything matches, including ä ö ü ß.
- iPadOS keeps some shortcuts for itself (⌘-Tab, ⌘-Space, Globe key, ⌘-H …); those never reach UniversePen.
- Some ISO keyboards report `^` and `<` swapped → Settings → Keyboard → "Swap the ^ and < keys".
- **Trackpad / mouse on the iPad** (confirmed on real hardware, Logi Combo Touch) controls the Mac pointer: absolute position (where the iPad pointer is over the image), click, two-finger click = right-click, double/triple click, drag, two-finger scroll, pinch/rotate like the finger gestures. The iPad pointer is hidden (the Mac cursor is visible in the video) – can be turned off. Keyboard modifiers also apply to clicks (e.g. ⌥-drag).
- **On-screen keyboard** (… menu): sends typed text as Unicode (independent of the Mac layout), without autocorrect.
- Held keys are released on disconnect and when opening settings, so nothing gets "stuck" on the Mac.

## Other known limits

- **Mirroring, not an extended display**, in all modes except the experimental "Second screen" (see above).
- **Window mode:** the position is tracked every 0.5 s; if the window is resized, restart the stream (switch the mode briefly).
- **Tilt direction** hasn't been checked on real hardware → invert switches for X and Y.
- **Zoom mapping in Affinity:** whether ⌘+scroll or ⌥+scroll zooms depends on Affinity's settings → selectable.
- **Latency display:** "RTT" is the real network round-trip time. "Frame" is the age of a frame on arrival (capture + encoding + network), estimated via a clock sync over ping; decoding and display (typically a few ms) are not included.
- **Mouse pointer** is streamed too (helps with hover).
- **Tablet identity:** UniversePen reports its own, made-up vendor ID and doesn't pretend to be Wacom. Apps that only accept certain vendors would then ignore pressure.

---

## Phase 5: Test plan on real hardware

Please go through in order and note each result:

1. **Connection:** pair, connect. Status display (… → "Show status"): RTT on Wi-Fi typically < 10 ms, 60 fps while moving.
2. **Image:** "iPad region" mode → no black bars, sharp? The encoder line on the Mac should say "Hardware · Low-Latency-RC".
3. **Pen test window** (Mac: "Open Pen Test …", move it into the region) – this is the decisive check whether macOS gets the data:
   - hover → `tabletProximity: in`, then `hover` lines
   - draw with varying pressure → `subtype=tabletPoint`, `pressure` changes, line width varies
   - tilt the pen → `tilt` changes; check the direction, use the invert switch if needed
   - roll the Pencil Pro → `rotation` changes
4. **Affinity:** brush with pressure→size (brush dynamics), stroke light → firm. Then tilt/rotation dynamics if the brush uses them.
   - If step 3 shows pressure but Affinity doesn't: Affinity ignores synthetic tablet events → document as a limitation.
5. **Gestures:** pan with two fingers, pinch to zoom (adjust the zoom method), two-/three-finger tap = undo/redo.
6. **Squeeze / double-tap** → the configured action in Affinity (default: double-tap = eraser E, squeeze = undo).
7. **Drop case:** turn off Wi-Fi on the iPad mid-stroke → the mouse button on the Mac must not stay "stuck".

## Phase 7: Optimisation ideas (not implemented yet)

- Video over UDP/DTLS instead of TCP (no waiting for lost packets).
- Adapt the bitrate automatically to RTT/backlog.
- Dirty-region detection to save bandwidth on still images (ScreenCaptureKit hardly delivers frames when nothing changes anyway).
- Per-device keys for revoking devices individually.

## External control & protocol

- **[UniversePen SDK](SDK/README.md) – MIT licence, free for anyone to use:** local developer API (switch it on in the Mac app, `127.0.0.1:47800` only) with an **Input API** (pressure, tilt, rotation, hover, touch, gestures live), a **Display API** (mode, second screen, resolution, frame rate, connection status) and a **Control API** (shortcuts, app profiles, pressure curves, all iPad settings). Swift package `UniversePenKit`, examples in Python, JavaScript and Swift. Tested on real hardware (2026-11-15).
- [`docs/API.md`](docs/API.md): `universepen://…` URLs for Shortcuts, Terminal, Stream Deck (switch mode, pair).
- [`docs/PROTOCOL.md`](docs/PROTOCOL.md): the complete wire protocol – the basis for your own clients/hosts (e.g. Android, Windows).

## Languages & translations

The apps have their own language picker (first step of the setup, later in the settings), independent of the system language. The default is English.

- Texts live in `Packages/TafelKit/Sources/TafelKit/Translations*.swift`; each key is the original German text.
- `python3 Tools/check-l10n.py` lists missing translations.
- **Found a mistake?** Most translations are machine-made. Please open an issue with the "Translation fix" template (language, where in the app, current text, suggestion) – or send a pull request for the matching table directly.

## Licence

Copyright © 2026 Biene

UniversePen is free software under the **GNU General Public License v3.0** (see [`LICENSE`](LICENSE)): you may use, modify and share the code. If you distribute a modified version, you must publish its source code under the GPL-3.0 as well. There is no warranty.

Exception: the [`SDK/`](SDK) folder (developer SDK, examples, API description) is under the **MIT licence** ([`SDK/LICENSE`](SDK/LICENSE)) and may also be used in closed-source programs.
