# NotchPrompter

A menu bar teleprompter for macOS. It shows your script in a black box that hangs from the MacBook notch, right next to the camera, so you can read while you keep eye contact. The overlay is hidden from screen sharing and screen recording.

Local only. No network, no accounts, no analytics.

> Status: overlay, fixed-speed scrolling, editor, settings, hotkeys and voice-activated scrolling work. Word tracking is **experimental**: it passes offline tests but isn't reliable with live speech yet.

## Requirements

- macOS 14 or later, Apple Silicon
- Xcode (command line tools alone are not enough, the build uses `xcodebuild`)
- XcodeGen: `brew install xcodegen`

## Build and run

```bash
make run        # generate the Xcode project, build Release, (re)launch the app
./run.sh        # same thing
make install    # copy to /Applications and launch
make clean
make voice-sim    # offline test of voice detection with synthesized Czech + English speech
make tracker-sim  # offline test of word tracking with a simulated speaker and recognizer
```

Build output goes to `~/Library/Developer/NotchPrompter/DerivedData`, outside the project folder. The project is on an iCloud-synced Desktop, and iCloud adds extended attributes that make `codesign` fail with *"resource fork, Finder information, or similar detritus not allowed"*.

The app is signed ad hoc (`-`), so you don't need a developer account. To open it in Xcode, run `xcodegen generate` and open `NotchPrompter.xcodeproj`.

## Using it

The app lives in the menu bar (centred-text icon, no Dock icon). From the menu you can start, pause or stop, show or hide the overlay, pick a script, and open the editor or settings.

Default global hotkeys work in any app, and you can change them in Settings → Hotkeys:

| Action | Default |
|---|---|
| Play / pause (with a 3-2-1 countdown on start) | ⌃⌥P |
| Speed up / slow down (±10 wpm) | ⌃⌥→ / ⌃⌥← |
| Scroll back / forward | ⌃⌥↑ / ⌃⌥↓ |
| Stop & rewind | ⌃⌥R |
| Show / hide overlay | ⌃⌥O |

Play/pause is not ⌃⌥Space because macOS already uses that shortcut to switch input sources.

- **Hover to pause.** Mouse clicks pass through the overlay to whatever is underneath. Moving the cursor over it pauses scrolling until you move away.
- **Speed** is in words per minute. The app converts it to points per second from the measured height of the laid-out text, so the pace stays the same when you change the font size or width.
- **Modes** (menu → Mode, or Settings → Scrolling):
  - *Fixed speed* scrolls continuously at the wpm you set.
  - *Voice-activated* scrolls at the same wpm, but only while the microphone hears you speak above a threshold. The text eases in and out instead of jumping, and it keeps moving through short pauses between words (about 0.45 s) so it doesn't stutter. A small mic glyph in the overlay's corner means it's waiting for your voice.
  - *Word tracking* (experimental) listens to what you say, follows you through the script, highlights the word you just said in yellow and dims the words you've already read. The line with the next word stays at the top, right under the camera. Pause and the text waits; go off-script and it waits until you're back; skip a sentence and it catches up within a word or two. If you skip much further (a whole paragraph), it finds you again after about five matching words; ⌃⌥↑/↓ jumps there faster, and tracking continues from the line you jump to.
- **Word tracking languages:** Čeština (cs-CZ), English (US) and English (UK); choose one in Settings → Scrolling. Recognition always runs on this Mac:
  - On **macOS 26 and later** the app uses Apple's on-device `SpeechAnalyzer` with `DictationTranscriber`. If the language's speech model isn't installed yet, the app asks whether to download it as soon as you choose word tracking or press play (also available from the menu and from Settings → Scrolling). macOS downloads the model once, the same way it adds a dictation language, and tracking starts automatically when it's done. English is usually already installed; Czech typically needs this download.
  - On **macOS 14–25** it uses `SFSpeechRecognizer` with on-device recognition required. Apple has no on-device Czech model for that API, so on those versions Czech shows "needs macOS 26" instead of silently sending audio to Apple's servers.
  - If tracking can't run (no model yet, no permission), the text scrolls at fixed speed and a caption at the bottom of the overlay says why (or shows download progress). The menu shows the same message.
  - *Test recognition* in Settings shows what the recognizer hears, without playing.
- **How speech is detected:** the app keeps measuring the background noise level and treats anything clearly louder than it as speech. This works the same with a quiet built-in mic at low input volume, a loud headset, or a noisy room; you don't need to change the system input volume. The mic starts listening during the countdown, which gives it time to learn the room before the text moves.
- **Sensitivity** (Settings → Scrolling, voice mode) is how far above the background your voice must be: from +18 dB (only clear, loud speech) to +6 dB (picks up quiet speech). The default is +12 dB. Turn on *Test microphone* to watch a live level bar: it turns green when you count as speaking, and the vertical tick marks the current threshold. Use headphones in calls, otherwise other people's voices from your speakers will move the text too.
- **Troubleshooting voice mode:** each time the mic stops, the app writes level statistics (no audio) to `~/Library/Application Support/NotchPrompter/voice-diagnostics.txt`. It lists the input device, level percentiles, the noise floor and threshold, and how much of the time you counted as speaking.
- **Scripts:** the editor (menu → Open Editor…) lists scripts on the left with a plain-text editor on the right. Toolbar buttons: new script, new script from the clipboard, import `.txt`/`.md` (markdown syntax is removed), delete.
- **Storage:** `~/Library/Application Support/NotchPrompter/scripts.json` and `settings.json`.

## Hidden from screen sharing

The overlay window sets `NSWindow.sharingType = .none`, and the window server reports it with sharing state `none` (`kCGWindowSharingState = 0`). Screen capture APIs that respect this flag (ScreenCaptureKit, `screencapture`, QuickTime, and the conferencing apps built on them) leave the window out. You still see it on your own screen.

### Verify it yourself

1. **Screenshot:** press ⌘⇧3. The overlay should be missing from the image.
2. **QuickTime:** File → New Screen Recording, record the built-in display for a few seconds while the overlay scrolls, then play it back. The overlay should not appear.
3. **Zoom / Google Meet / Microsoft Teams:** start a meeting (alone is fine) and share your **entire screen**, not a single window. Check what you're sending:
   - Zoom: the shared screen preview, or join the same meeting from your phone.
   - Meet: join the same meeting from a second device or a browser profile.
   - Teams: join from the mobile app or a second account.

   The text should be visible to you and missing for everyone else.

To compare against a capture that *does* include the overlay:

```bash
defaults write com.matejlakomy.NotchPrompter AllowScreenCapture -bool YES   # then relaunch
defaults delete com.matejlakomy.NotchPrompter AllowScreenCapture            # back to hidden
```

### Limitations

- `sharingType = .none` is a request to well-behaved capture clients. It is not DRM. Software that reads the frame buffer differently, a capture card, or a phone pointed at the screen will still see the overlay.
- Developers report mixed results with ScreenCaptureKit on macOS 15 and later. In one Apple forum thread, the ScreenCaptureKit sample app briefly showed a `NSWindowSharingNone` window after its capture filter was changed, and hid it again after a stream restart ([Apple Developer Forums #808016](https://developer.apple.com/forums/thread/808016)). OBS display capture has also been reported to capture such windows. Test with the exact app and macOS version you use before you rely on it.
- On a non-notched display (for example an external monitor as the only screen), the overlay sits at the top centre of the screen instead of under a notch.

## Permissions

- **Global hotkeys** need no permission. They use Carbon hot keys, which don't require Accessibility access.
- **Microphone:** macOS asks the first time you switch to *Voice-activated* mode, not at launch. The mic runs only while voice mode is playing (or while *Test microphone* is on), so the orange recording dot in the menu bar shows only then. The app computes only the loudness level; it records nothing and sends nothing anywhere.
  - If you deny access, voice mode falls back to fixed speed and the menu shows a warning. To turn access back on, go to System Settings → Privacy & Security → Microphone (Settings has a shortcut button).
  - To reset the prompt during development: `tccutil reset Microphone com.matejlakomy.NotchPrompter`.
- **Speech Recognition:** macOS asks for Microphone and Speech Recognition access the first time you choose *Word tracking*. The microphone runs only while word tracking is playing or *Test recognition* is on. Speech is recognized on-device and nothing is stored.

Because the app is signed ad hoc, a rebuild changes its code signature and macOS may ask for permission again.

## Project layout

```
project.yml                 XcodeGen spec (LSUIElement, usage descriptions, KeyboardShortcuts package)
Makefile, run.sh            build / run from the terminal
NotchPrompter/
  App/        NotchPrompterApp (MenuBarExtra + windows), AppState (wiring), MenuBarMenu
  Overlay/    OverlayWindow (NSPanel + controller), OverlayView, NotchShape, NotchGeometry, OverlayLayout
  Scrolling/  ScrollEngine (CADisplayLink, wpm → pt/s or follow target, countdown), ScrollingTextView (offset,
              fades, word highlight), TextLineMap (line positions from SwiftUI's own text layout)
  Scripts/    Script, ScriptStore (JSON), ScriptImporter (.txt/.md), ScriptTokens (words + normalization), EditorView
  Settings/   PrompterSettings, SettingsStore (JSON), SettingsView
  Hotkeys/    HotkeyManager (KeyboardShortcuts names + handlers)
  Voice/      VoiceDetector (AVAudioEngine input → level), SpeechGate (noise-floor tracking, attack/release),
              VoiceDiagnostics (level statistics file),
              SpeechTracker (mic → recognizer → current word), WordMatcher (aligns recognized words with the script),
              SpeechBackend (SFSpeechRecognizer, on-device only), AnalyzerSpeechBackend (macOS 26+ SpeechAnalyzer),
              SpeechPermissions
Tools/SpeechGateSim/        offline simulation behind `make voice-sim`
Tools/TrackerSim/           offline simulation behind `make tracker-sim`
  Support/    Persistence, observe() helper, DebugSnapshot, Info.plist (generated)
```

### Development aid

```bash
open ~/Library/Developer/NotchPrompter/DerivedData/Build/Products/Release/NotchPrompter.app --args -SnapshotDir /tmp/np
```

This renders the overlay off screen to PNGs (idle, countdown, scrolling, nudged) and writes `state.txt` with the engine state. It needs no Screen Recording permission.

To exercise word tracking without a microphone, stream an audio file through the real recognizer and matcher in real time; the word index after each recognizer event goes to `state.txt`:

```bash
make voice-sim   # creates en.wav / cs.wav with macOS `say`
open ~/Library/Developer/NotchPrompter/DerivedData/Build/Products/Release/NotchPrompter.app --args \
  -SnapshotDir /tmp/np \
  -TrackerTestFile ~/Library/Developer/NotchPrompter/DerivedData/voice-sim/en.wav \
  -TrackerTestScript "Hello and welcome back. Today I want to show you how this teleprompter works, right under the camera." \
  -TrackerTestLanguage en-US
```
