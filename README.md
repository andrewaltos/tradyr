# Tradyr

Live captions and French ↔ English translation for macOS, shown in a small always-on-top overlay.
Everything runs on-device: speech recognition is Apple's `SpeechAnalyzer`, translation is Apple's
Translation framework, and no audio or text leaves the Mac.

I built it to follow phone calls with French speakers. It also works for captioning any single
audio source, such as a video or a talk.

> **Status:** a personal side project at v0.1. It works and I use it, but it's rough in places,
> unsigned, and only tested on my own setup. Expect to build it yourself. See
> [Caveats](#caveats) for known limitations.

## What it does

Tradyr is a menu-bar app with no Dock icon. Pick a mode and press **Start**:

- **Single input** (default) captions one source, in either direction (FR → EN or EN → FR). The
  source can be the microphone, **All Applications**, or any running app by name (Safari, Edge, …).
- **Phone call** listens to two sources at once. **Them** is the call audio from "Calls from
  iPhone" on the Mac, and **You** is the microphone. Both are translated from French to English,
  so you can check what you said as well as what you heard.

While it runs, the overlay shows a scrolling history with the newest caption at the bottom: the
recognised text in small type, the translation larger, and a level meter for each source. You can
drag, resize and scroll it, and it has a **Stop translation** button. Paragraphs break after
questions and every few sentences.

Each session is saved as a markdown file with both languages. **History** in the menu opens a
window for browsing past sessions.

## Requirements

- macOS 26 or later
- Xcode command-line tools (full Xcode is not needed)
- French and English speech and translation models, downloaded from inside the app on first run

## Build and run

```sh
make identity         # once: creates a self-signed cert so permissions survive rebuilds
make run              # build, bundle, sign, install to /Applications, launch
```

Other targets:

```sh
make bundle           # build .build/Tradyr.app without installing
make install          # build and replace /Applications/Tradyr.app (quits the running copy)
make test
make verify-offline   # checks the built binary for network or telemetry symbols
make reset-perms      # clears the mic, speech and system-audio permissions
make icon             # rebuilds the icon from Resources/AppIcon.png
```

**First run:** open **Language packs…** from the menu and download them, then press **Start**.
macOS asks for Microphone, Speech Recognition and System Audio Recording access.

### Why the self-signed certificate

macOS ties those permissions to the app's code signature. An ad-hoc signature changes on every
build, so every rebuild would ask for permissions again. `make identity` adds a local certificate
called "Tradyr Local" to your login keychain and marks it as trusted for code signing (expect two
password prompts). If the certificate is missing, builds fall back to ad-hoc signing and print a
warning.

The bundle is deliberately not signed with the hardened runtime, which would need an audio-input
entitlement before the microphone works. It is not notarized.

### Build quirks

- `make test` passes the swift-testing macro plugin path to the compiler explicitly. Plain
  `swift test` fails intermittently with "plugin for module 'TestingMacros' not found", because
  SwiftPM doesn't look where the command-line tools install it.
- `@State` isn't available without Xcode (its macro plugin ships only with Xcode), so view-local
  state lives on `@Observable` models.
- The version comes from `VERSION` and is written into `Info.plist` at bundle time.
- `Resources/AppIcon.png` is the 1024×1024 icon source. If it's missing, a placeholder is generated.

## Sessions

Sessions are saved to `~/Documents/Tradyr/Sessions/<date weekday>/<HH.mm.ss>.md`, one file per
session. Audio is never stored. Turn off **Save transcript** in the menu to stop saving.

Call transcripts contain other people's words. They are plain files on your disk and are never
uploaded, but whether you keep them, and whether you tell the other person, is up to you.

## Diagnostics

`tradyr-probe` runs an audio file through the same recognise → translate pipeline, without a mic:

```sh
swift run tradyr-probe clip.aiff fr        # FR → EN
swift run tradyr-probe clip.aiff fr 2      # two lanes at once on the same file
swift run tradyr-probe --apps              # running apps and the audio processes behind each
swift run tradyr-probe --parse file.md     # how the History window parses a session file
```

To see the app's own logs (mic format, restarts):

```sh
log stream --predicate 'subsystem == "dev.tradyr.app"'
```

## Project layout

| Path | Contents |
|---|---|
| `Sources/TradyrCore` | Audio sources, recogniser wrapper, paragraph splitting, translation, lane pipeline, session store and parser |
| `Sources/Tradyr` | Menu-bar app, overlay, History and Language packs windows |
| `Sources/tradyr-probe` | The diagnostics CLI |
| `Tests/TradyrCoreTests` | Transcript format, session store, paragraph splitting, document parser |
| `Resources/` | `Info.plist` template, permission strings, icon source |
| `Scripts/` | Bundle assembly, icon generation, signing identity |

## Caveats

- **Private API.** To match an app to the helper processes that play its audio (for example
  Safari's `com.apple.WebKit.GPU`), Tradyr calls `responsibility_get_pid_responsible_for_pid`,
  with a bundle-id fallback. Apple could change or remove it.
- **Echo in call mode.** If the call plays through speakers, the mic also picks up the other
  person and their words can appear twice. Use headphones.
- **Call audio comes from a system daemon.** During a "Calls from iPhone" call, the other
  person's audio is played by `com.apple.avconferenced`, not the FaceTime or Phone app, so that is
  what call mode captures. A macOS update could change this.
- **Output-device changes mid-session** (plugging in headphones, connecting Bluetooth) aren't
  handled for app or call audio. Stop and start the session again.
- **Speaker changes** are only detected when someone asks a question. There is no speaker
  identification.
- **The recogniser smooths speech.** On the **You** lane it can show what you probably meant
  rather than exactly what you said, so it isn't a pronunciation checker.
- **Settings don't persist** between launches yet.
