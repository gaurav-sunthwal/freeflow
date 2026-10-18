<p align="center">
  <img src="Resources/icon/icon-1024.png" width="128" alt="FreeFlow icon">
</p>

<h1 align="center">FreeFlow</h1>

<p align="center">
  <b>Free, private voice typing for Mac.</b><br>
  Hold a key, speak in any app, let go: clean, punctuated text appears where your cursor is.<br>
  No account, no subscription, no cloud. Everything runs on your Mac.
</p>

---

## Install

Open **Terminal** and paste:

```bash
curl -fsSL https://raw.githubusercontent.com/gaurav-sunthwal/freeflow/main/install.sh | bash
```

This downloads the source, builds FreeFlow on your Mac, installs it to **Applications** and opens it.
The temporary download is deleted afterwards; there's nothing else to keep around.

<details>
<summary>Or install from a clone</summary>

```bash
git clone https://github.com/gaurav-sunthwal/freeflow.git
cd freeflow
./install.sh
```

Once it's installed you can delete the `freeflow` folder. The app in Applications is self-contained.
</details>

**Requirements:**
- A Mac with Apple silicon (M1 or newer)
- macOS 26 or later
- Apple's free developer tools. If you don't have them, the installer opens the installation window for you; run it
  again when that finishes.
- Optional: Apple Intelligence turned on, for self-corrections and Command Mode

### First launch

1. Grant **Microphone**, **Accessibility** and **Speech Recognition** in the Setup window.
2. In **System Settings → Keyboard**, set **"Press 🌐 key to"** to **Do Nothing**.
3. Click into any text box, **hold `fn`**, speak, and let go.

Optionally, turn on **Launch FreeFlow at login** in FreeFlow → Settings.

## Features

| | |
|---|---|
| **Push-to-talk** | Hold `fn` (or Right ⌥ / ⌘ / ⌃), speak, release to insert |
| **Hands-free** | Double-tap `fn` to keep listening, then tap again to finish. `esc` cancels |
| **Command Mode** | Select text, hold `control` + `fn`, and say "make this more formal", "turn into bullets", "translate to Hindi". With nothing selected, it writes new text |
| **Self-corrections** | "Meet Tuesday. Actually no, make it Wednesday" → "Meet Wednesday." Also "scratch that" and "I mean…" |
| **Clean text** | Filler words removed, punctuation added, "new line" / "new paragraph" |
| **Dictionary** | Teach it names and jargon, and auto-fix words it mishears |
| **Snippets** | Say "my calendar link" and your full booking URL is inserted |
| **Styles** | Optional AI mode that adapts tone to email, chat, code or docs |
| **History & stats** | Searchable history, words dictated, WPM and day streak |
| **25 languages** | English, Hindi, Spanish, French, German, Japanese, Chinese, Tamil, Telugu, Bengali, Marathi and more |

## Privacy

- Speech-to-text runs on-device with Apple's **SpeechAnalyzer**. Audio is never uploaded or saved.
- AI corrections and Command Mode use Apple's on-device **Foundation Models**.
- There's no account, analytics or telemetry, and no network access except a one-time language-model download from Apple.
- Your history is stored at `~/Library/Application Support/FreeFlow/history.json`.

Want different models? In Settings you can point FreeFlow at a local
[whisper.cpp](https://github.com/ggml-org/whisper.cpp) server or a local LLM through
[Ollama](https://ollama.com) or LM Studio.

## Updates

FreeFlow updates itself. A few times a day it checks for a new release on GitHub. When it finds one, it builds
the release in the background, waits until you aren't dictating, then restarts as the new version. Your history,
settings and permissions are kept.

- Check right away: menu-bar icon → **Check for Updates…**
- Turn auto-updates off: FreeFlow → Settings → Updates.

Versions older than 1.1.0 don't have the updater yet. Run the install command once more to get it.

## Uninstall

```bash
curl -fsSL https://raw.githubusercontent.com/gaurav-sunthwal/freeflow/main/uninstall.sh | bash
```

This removes the app but keeps your history and settings. To delete everything, including history, dictionary,
snippets, settings and permissions, add `--purge`:

```bash
curl -fsSL https://raw.githubusercontent.com/gaurav-sunthwal/freeflow/main/uninstall.sh | bash -s -- --purge
```

## Troubleshooting

| Problem | Fix |
|---|---|
| Holding `fn` does nothing | Menu-bar icon → **Setup & Permissions**. If Accessibility is on but it still doesn't work, remove FreeFlow from System Settings → Privacy & Security → Accessibility, add it again, and relaunch |
| Emoji picker pops up | System Settings → Keyboard → "Press 🌐 key to" → **Do Nothing**, or choose another hotkey in Settings |
| Permissions reset after updating | Happens once when moving from a version older than 1.1.0. After that, permissions are kept across updates |
| "Developer tools are too old" | Update Xcode or the Command Line Tools to 26+ via Software Update |
| Corrections / Command Mode don't work | Turn on Apple Intelligence in System Settings → Apple Intelligence & Siri |

## How it works

```
hold fn ──► CGEventTap ──► AVAudioEngine ──► SpeechAnalyzer (on-device, streamed live)
                                                   │
release ──► rules (fillers, "scratch that", snippets, dictionary)
                                                   │
            on-device LLM, only for self-corrections or Command Mode (with safety checks)
                                                   │
            clipboard snapshot → ⌘V into the focused app → clipboard restored
```

| File | Purpose |
|---|---|
| `Sources/FreeFlow/Coordinator.swift` | Hotkey → record → transcribe → clean → insert |
| `Sources/FreeFlow/HotkeyMonitor.swift` | Push-to-talk, double-tap, Command Mode, Esc |
| `Sources/FreeFlow/Transcriber.swift` | Apple SpeechAnalyzer streaming, plus Whisper-server support |
| `Sources/FreeFlow/TextProcessor.swift` | Rules, snippets, dictionary, self-corrections, LLM safety checks |
| `Sources/FreeFlow/TextInserter.swift` | Clipboard-safe paste and selected-text capture |
| `Sources/FreeFlow/Overlay.swift` | The floating "Flow bar" |
| `Sources/FreeFlow/MainView.swift` | Home, Dictionary, Snippets, Style, Settings, Setup |

## Development

```bash
./build.sh                    # builds dist/FreeFlow.app
./build.sh --install          # builds, installs to /Applications and launches
B=dist/FreeFlow.app/Contents/MacOS/FreeFlow
$B --process "Send it to John, I mean Sarah, by Friday."    # test the text pipeline
say -o /tmp/t.aiff "hello world new line second line" && $B --selftest /tmp/t.aiff
./make-dmg.sh                 # optional: packaged DMG (Developer ID + NOTARY_PROFILE to notarize)
```

### Publishing a release

```bash
./release.sh 1.2.0 "Faster corrections and a new mic picker"
```

This sets the version, checks that the app builds, commits, tags `v1.2.0`, pushes, and creates the GitHub release.
Installed copies pick it up automatically. Pushes to `main` without a release don't reach existing users,
so you can push work in progress safely.

Contributions are welcome. Open an issue or a pull request.

## License

[MIT](LICENSE). Free to use, modify and share.
