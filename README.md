# gab

Push-to-talk Whisper dictation for macOS. Hold a key, talk, release — text pastes
at the cursor. Runs Whisper locally, offline, zero cost. Menu bar only, no Dock icon.

Default hotkey: **hold right-Option**.

## Build & run (no Xcode project needed)

This is a plain `swiftc` + Makefile build that produces a `.app` bundle — there is
no `.xcodeproj` to open.

```bash
# 1. Build the vendored whisper.cpp static libs (once, ~1–2 min)
make whisper

# 2. Create a stable signing identity (once) so the Accessibility grant
#    persists across rebuilds instead of resetting every build.
make sign

# 3. Download a model into ~/Library/Application Support/gab/
./scripts/fetch-model.sh large-v3-turbo   # ~1.5GB, best accuracy (preferred)
# or: ./scripts/fetch-model.sh base.en     # ~140MB, fast first run

# 4. Build and launch
make run
```

`make run` builds `build-app/gab.app` and opens it. A mic icon appears in the menu bar.

gab auto-selects the best model present (`large-v3-turbo` > `base.en`); override with
`GAB_MODEL=/full/path/to/ggml-*.bin`.

**Signing:** if you skip `make sign`, the build falls back to ad-hoc signing and macOS
will make you re-grant Accessibility after most rebuilds. `make sign` creates a local
self-signed `gab-dev` cert once; after that the grant sticks. Note that the *first*
build after switching signing changes gab's code identity, so you'll grant Accessibility
one final time — then never again.

## First-run permissions (one time)

macOS will prompt for two grants — gab needs both:

1. **Microphone** — accept the prompt on first dictation.
2. **Accessibility** — System Settings → Privacy & Security → Accessibility →
   enable **gab**. Required for the global hotkey (CGEventTap) and synthetic Cmd+V.

gab polls for the grant and enables the hotkey the moment you toggle it on — no
relaunch needed. The menu bar item shows live status
(`needs Accessibility permission` → `hold right-Option to dictate`).

gab also registers itself to **Start at Login** (toggle in the menu).

## Install as a standalone app

```bash
make install      # copy gab.app into /Applications (launch from Spotlight/Launchpad)
```

gab is a menu-bar app, so it lives in the menu bar (no Dock icon) — installing just
makes it a normal app you can launch and that starts at login.

## Make a shareable build

```bash
make release      # self-contained app with the model bundled inside Resources
make dmg          # drag-to-install build-app/gab.dmg (implies release)
```

`make dmg` bundles `small.en` into the app (set `RELEASE_MODEL` in the Makefile to
change), so the recipient needs no model download — just drag gab to Applications.

**Compatibility:** the build targets **macOS 13.0+** (Apple Silicon, arm64). This is
set explicitly — both the Swift build (`-target arm64-apple-macos13.0` in the Makefile)
and whisper.cpp (`CMAKE_OSX_DEPLOYMENT_TARGET` in setup-whisper.sh) — because tools
otherwise default the minimum-OS to the *build host's* macOS version, which makes the
app refuse to launch on older Macs ("you need to update macOS"). If you ever need to
support Intel Macs too, the build must be made universal (arm64 + x86_64).

**Giving it to someone else:** the build is signed with your local `gab-dev`
certificate, which other Macs don't trust. On first launch a recipient must
**right-click the app → Open → Open** to get past Gatekeeper (once per install).
For a build that opens with zero warnings on any Mac, you need a paid Apple
Developer account, a Developer ID certificate, and notarization — not set up here.

Either way, every user must grant **Microphone** and **Accessibility** on first run —
that's macOS's permission model and is unavoidable for any app of this kind.

## Use

1. Click into any text field.
2. Hold **right-Option** and speak. The menu bar icon turns red.
3. Release. The transcription pastes at the cursor.

Clips shorter than ~300ms are dropped (avoids Whisper hallucinating on quick taps).

## Layout

```
Sources/gab/         Swift app (menu bar, hotkey, audio, whisper, paste)
Sources/CWhisper/    C module map bridging whisper.cpp into Swift
scripts/             setup-whisper.sh, fetch-model.sh
Resources/Info.plist LSUIElement + mic usage string
vendor/              whisper.cpp clone + built static libs (gitignored)
Makefile             build the .app
```

To change the model, set `GAB_MODEL=/full/path/to/ggml-*.bin` before launching, or
drop a `ggml-base.en.bin` into `~/Library/Application Support/gab/`.

## Later (not yet built)

- Configurable hotkey (incl. double-tap-and-hold)
- Toggle mode (tap to start/stop) for long dictation
- Model switcher UI
- Richer clipboard restore (preserve non-text pasteboard contents)
- Silence-trim + no-speech confidence gate for noisy-room hallucinations
- Prompt-shaping pass for piping into coding agents
