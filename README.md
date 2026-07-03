# gab

Push-to-talk Whisper dictation for macOS. Hold a key, talk, release — your words paste
in at the cursor. Whisper runs locally and offline, so dictation is private and free to
run. gab lives in the menu bar with no Dock icon.

- **Push-to-talk** — hold right-Option, speak, release. That's the whole interaction.
- **Local & offline** — speech never leaves your Mac. No accounts, no network, no cost.
- **Menu-bar only** — no Dock icon; optional start-at-login.
- **Apple Silicon native** — Metal-accelerated whisper.cpp.

Default hotkey: **hold right-Option**.

## Requirements

- macOS 13.0 or later
- Apple Silicon (arm64) Mac
- Xcode Command Line Tools (`swiftc`) and CMake, to build from source

## Quick start

This is a plain `swiftc` + Makefile build that produces a `.app` bundle — there is no
`.xcodeproj` to open.

```bash
# 1. Build the vendored whisper.cpp static libs (once, ~1–2 min)
make whisper

# 2. Create a stable signing identity (once) so the Accessibility grant
#    persists across rebuilds instead of resetting every build.
make sign

# 3. Download a model into ~/Library/Application Support/gab/
./scripts/fetch-model.sh large-v3-turbo   # ~1.5 GB, best accuracy (preferred)
# or: ./scripts/fetch-model.sh base.en     # ~150 MB, fast first run

# 4. Build and launch
make run
```

`make run` builds `build-app/gab.app` and opens it. A mic icon appears in the menu bar.

**Signing:** if you skip `make sign`, the build falls back to ad-hoc signing and macOS
will make you re-grant Accessibility after most rebuilds. `make sign` creates a local
self-signed `gab-dev` cert once; after that the grant sticks. The *first* build after
switching signing changes gab's code identity, so you'll grant Accessibility one final
time — then never again.

## Models

Whisper models are **not** bundled with the source (they're large binaries, kept out of
git). Download one yourself — the easiest way is the fetch script:

```bash
./scripts/fetch-model.sh large-v3-turbo   # or: base.en, small.en, tiny.en, large-v3
```

It saves to `~/Library/Application Support/gab/`, where gab picks it up automatically —
the model then appears in the menu bar **Model** submenu.

Prefer to download by hand? Every model comes from the official whisper.cpp collection on
Hugging Face — [ggerganov/whisper.cpp](https://huggingface.co/ggerganov/whisper.cpp/tree/main).
Drop the `.bin` into `~/Library/Application Support/gab/`:

| Model | Size | Notes | Direct download |
|-------|------|-------|-----------------|
| `ggml-large-v3-turbo.bin` | ~1.5 GB | Accurate, preferred | [download](https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo.bin) |
| `ggml-small.en.bin` | ~465 MB | Balanced | [download](https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.en.bin) |
| `ggml-base.en.bin` | ~150 MB | Fast, good first run | [download](https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.en.bin) |
| `ggml-tiny.en.bin` | ~75 MB | Fastest, least accurate | [download](https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-tiny.en.bin) |
| `ggml-large-v3.bin` | ~3 GB | Slowest, most accurate | [download](https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3.bin) |

gab auto-selects the best model present (`large-v3-turbo` > `small.en` > `base.en`).
To force a specific one, set `GAB_MODEL=/full/path/to/ggml-*.bin` before launching.

## Permissions (first run)

macOS will prompt for two grants — gab needs both:

1. **Microphone** — accept the prompt on first dictation.
2. **Accessibility** — System Settings → Privacy & Security → Accessibility →
   enable **gab**. Required for the global hotkey (CGEventTap) and synthetic Cmd+V.

gab polls for the grant and enables the hotkey the moment you toggle it on — no relaunch
needed. The menu bar item shows live status (`needs Accessibility permission` →
`hold right-Option to dictate`). gab can also register itself to **Start at Login**
(toggle in the menu).

## Usage

1. Click into any text field.
2. Hold **right-Option** and speak. The menu bar icon turns red.
3. Release. The transcription pastes at the cursor.

Clips shorter than ~300 ms are dropped, which avoids Whisper hallucinating on quick taps.

## Install as a standalone app

```bash
make install      # copy gab.app into /Applications (launch from Spotlight/Launchpad)
```

gab is a menu-bar app, so it lives in the menu bar (no Dock icon) — installing just makes
it a normal app you can launch and that starts at login.

## Distributing to others

```bash
make release      # self-contained app with the model bundled inside Resources
make dmg          # drag-to-install build-app/gab.dmg (implies release)
```

`make dmg` bundles `small.en` into the app (set `RELEASE_MODEL` in the Makefile to
change), so the recipient needs no model download — just drag gab to Applications.

**Compatibility:** the build targets **macOS 13.0+** (Apple Silicon, arm64). This is set
explicitly — both the Swift build (`-target arm64-apple-macos13.0` in the Makefile) and
whisper.cpp (`CMAKE_OSX_DEPLOYMENT_TARGET` in setup-whisper.sh) — because the tools
otherwise default the minimum OS to the *build host's* macOS version, which makes the app
refuse to launch on older Macs. To support Intel Macs too, the build must be made
universal (arm64 + x86_64).

**Gatekeeper:** the build is signed with your local `gab-dev` certificate, which other
Macs don't trust. On first launch a recipient must **right-click the app → Open → Open**
to get past Gatekeeper (once per install). For a build that opens with zero warnings on
any Mac, you need a paid Apple Developer account, a Developer ID certificate, and
notarization — not set up here.

Either way, every user must grant **Microphone** and **Accessibility** on first run —
that's macOS's permission model, unavoidable for any app of this kind.

## Project layout

```
Sources/gab/         Swift app (menu bar, hotkey, audio, whisper, paste)
Sources/CWhisper/    C module map bridging whisper.cpp into Swift
scripts/             setup-whisper.sh, fetch-model.sh
Resources/Info.plist LSUIElement + mic usage string
vendor/              whisper.cpp clone + built static libs (gitignored)
Makefile             build the .app
```

## Roadmap

- Configurable hotkey (incl. double-tap-and-hold)
- Toggle mode (tap to start/stop) for long dictation
- Model switcher UI
- Richer clipboard restore (preserve non-text pasteboard contents)
- Silence-trim + no-speech confidence gate for noisy-room hallucinations
- Prompt-shaping pass for piping into coding agents
