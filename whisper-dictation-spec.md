# Push-to-Talk Whisper Dictation ("gab") — Spec

Native macOS menu bar app. Hold a hotkey, talk, release, text pastes at the cursor. Runs Whisper locally. Zero cost, fully offline.

## Stack
- **Language:** Swift, AppKit (menu bar app, `LSUIElement` so no Dock icon)
- **Audio:** `AVAudioEngine` to capture mic, `AVAudioConverter` to resample to 16kHz mono float32
- **Hotkey:** `CGEventTap` watching `flagsChanged` (push-to-talk key is a modifier — see Hotkey)
- **Transcription:** `whisper.cpp` (bundle the binary + a `ggml` model, link via C interop) — recommended for a self-contained native app. Alternative: shell out to `mlx-whisper` if you want fastest setup over a single binary.
- **Paste:** clipboard write + `CGEvent` synthetic Cmd+V

## Core flow
1. App lives in the menu bar, no Dock icon, no window.
2. User clicks into any text field (focus is now there — app never steals focus).
3. User **holds** the hotkey → start recording mic, show a listening indicator.
4. User **releases** → stop recording, run Whisper on the captured buffer.
5. **Guard:** if the clip is shorter than ~300ms, drop it (avoids Whisper hallucinating phantom text on quick taps / silence).
6. Paste transcribed text at the cursor:
   - Save current clipboard contents
   - Write transcription to clipboard
   - Post synthetic Cmd+V via `CGEvent`
   - Restore previous clipboard contents (after paste completes — see gotchas)
7. Indicator clears. Focus never left the text field, so text lands in the right place.

## Hotkey
- Default: hold **right-Option** (`right-Cmd` and `fn` are load-bearing — see Why these choices). Hold-to-talk, not toggle.
- **Modifier keys do NOT emit keyDown/keyUp** — they arrive as `flagsChanged` events. Detect the press by:
  - Listen for `.flagsChanged` in the event tap.
  - Check the keycode (right-Cmd = 54, right-Option = 61, left-Option = 58) and whether that modifier's flag bit just turned **on** (press) or **off** (release).
  - `fn` is special: it's `maskSecondaryFn`, not a standard modifier mask — special-case it if you ever offer it.
- Make the key configurable later; hardcode one to start.

## Why these choices
- **Clipboard + Cmd+V**, NOT `AXUIElement` text insertion — clipboard paste works in every app (native, Electron, terminal, browser). AX insertion has spotty coverage.
- **CGEventTap**, NOT `NSEvent` global monitor — need real modifier down/up for hold-to-talk; global monitors are read-only and awkward for modifier hold.
- **right-Option as the trigger** — a key you hold for seconds should be inert. Right-Cmd held + any stray keypress fires a Cmd shortcut in the focused app; `fn` is the Globe key (emoji / dictation / input-switching) on most setups. Right-Option is far less load-bearing. (A double-tap-and-hold of a modifier is another good option for later.)
- App is `LSUIElement` and background-only so it never grabs focus from the target text field.

## Models — where to get them
**whisper.cpp (spec default):**
- `ggml`-format `.bin` files, hosted on Hugging Face under `ggerganov/whisper.cpp`
- Download via the repo script: `./models/download-ggml-model.sh large-v3-turbo`
- Or grab directly from the HF repo. Files named like `ggml-base.en.bin`, `ggml-large-v3-turbo.bin`

**mlx-whisper (if you switch engines):**
- Auto-downloads from HF on first run (e.g. `mlx-community/whisper-large-v3-turbo`) and caches. No manual download.

**Which model:**
- `base.en` — ~140MB, fast, fine for clean English mic input. Good for first run.
- `large-v3-turbo` — ~1.5GB, much better accuracy, still fast on Apple Silicon. The one to settle on.
- Skip plain `large-v3` — slower, turbo is nearly as accurate.

**Where to keep it:** load the model from `~/Library/Application Support/gab/` rather than baking it into the app bundle. Same "no runtime download" guarantee for a personal app, but keeps the app binary slim and avoids re-signing a 1.5GB blob on every build. (Bundling into Resources also works if you'd rather have one self-contained `.app`.)

## Permissions (one-time grants)
- **Microphone** — `NSMicrophoneUsageDescription` in Info.plist
- **Accessibility** — required for both CGEventTap and synthetic Cmd+V. System Settings → Privacy & Security → Accessibility. App should detect if not granted and prompt.

## Known gotchas
- **Audio format conversion** — `AVAudioEngine` gives you the hardware format (usually 44.1/48kHz). whisper.cpp wants **16kHz mono float32**. Run the tap buffer through an `AVAudioConverter` before handing it to Whisper, or transcriptions come back as garbage.
- **Whisper hallucinates on short/silent clips** — quick taps or near-silence reliably produce phantom text ("Thank you." / "you."). Enforce the ~300ms minimum-duration guard, and ideally trim leading/trailing silence before transcribing.
- **Event tap gets disabled by the system** — under load or timeout the OS disables your tap. Handle `kCGEventTapDisabledByTimeout` and `kCGEventTapDisabledByUserInput` by re-enabling the tap (`CGEvent.tapEnable`), or dictation silently dies after a while.
- **Secure input fields** (password fields) block synthetic events by design — won't work there, that's fine.
- **Clipboard restore** — don't restore on a blind 100ms timer; it races slow apps and clipboard managers. Restore after the paste has actually landed (poll `changeCount`, or use a comfortable delay ~150–250ms as a personal-app shortcut).
- **Model load** — load the Whisper model once at launch, keep it in memory; don't reload per dictation.
- **Listening indicator** — small menu bar state change or a tiny floating HUD; keep it non-focus-stealing (`NSPanel` with `.nonactivatingPanel`).

## v1 scope (one sitting — budget the time for integration plumbing, not app logic)
- Menu bar app, hold `right-Option` to dictate, paste at cursor, one model in Application Support.
- The Swift/AppKit app is small. The time sinks are: building/linking whisper.cpp + the C bridging header, the Accessibility permission dance, and the event tap. Plan accordingly.
- That's it. No settings pane, no model switcher, no waveform, no history. Ship that first.

## Later (only after v1 works)
- Configurable hotkey (incl. double-tap-and-hold)
- Model switcher
- Toggle mode (tap to start/stop) for long dictation
- Prompt-shaping pass for piping into coding agents
