<p align="center">
  <img src="Resources/icon/icon-1024.png" width="128" alt="FreeFlow icon">
</p>

<h1 align="center">FreeFlow</h1>

<p align="center">
  <b>Free, private voice typing for Mac.</b><br>
  Hold a key, speak in any app, let go: clean, punctuated text appears where your cursor is.<br>
  No account, no subscription, no cloud. Everything runs on your Mac.
</p>

<p align="center">
  <a href="https://freeflow-voice.vercel.app">Website</a> ·
  <a href="https://github.com/gaurav-sunthwal/freeflow/releases">Releases</a> ·
  <a href="https://github.com/gaurav-sunthwal/freeflow-website">Website source</a>
</p>

<p align="center">
  <a href="https://freeflow-voice.vercel.app"><b>🌐 freeflow-voice.vercel.app</b></a>
  &nbsp;·&nbsp;
  <a href="https://freeflow-voice.vercel.app/install">Install guide</a>
  &nbsp;·&nbsp;
  <a href="https://freeflow-voice.vercel.app/wispr-flow-alternative">FreeFlow vs Wispr Flow</a>
  &nbsp;·&nbsp;
  <a href="https://freeflow-voice.vercel.app/privacy">Privacy</a>
</p>

<p align="center">
  <a href="https://github.com/gaurav-sunthwal/freeflow/releases/latest"><img alt="Latest release" src="https://img.shields.io/github/v/release/gaurav-sunthwal/freeflow?color=7d6bff"></a>
  <a href="LICENSE"><img alt="MIT license" src="https://img.shields.io/badge/license-MIT-7d6bff"></a>
  <img alt="macOS 26+" src="https://img.shields.io/badge/macOS-26%2B-black?logo=apple">
  <img alt="Apple silicon" src="https://img.shields.io/badge/Apple%20silicon-M1%2B-black">
  <a href="https://freeflow-voice.vercel.app"><img alt="Website" src="https://img.shields.io/badge/website-freeflow--voice.vercel.app-7d6bff"></a>
</p>

FreeFlow is a free, open-source alternative to paid dictation apps like Wispr Flow. You get the same hold-to-talk
workflow (filler words removed, self-corrections, dictionary, snippets, rewriting by voice) with no word limits,
and speech recognition that runs on your Mac instead of in the cloud.
[See the full comparison →](https://freeflow-voice.vercel.app/wispr-flow-alternative)

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

Step-by-step instructions and troubleshooting are on the website:
[freeflow-voice.vercel.app/install](https://freeflow-voice.vercel.app/install).

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
| **Whisper Turbo** | Optional on-device Whisper model (one-time 550 MB download): much better with accents, tech words and background noise. Transcribes while you speak, so text is ready about 1.5 s after you stop |
| **Home dashboard** | Streak, words today, speaking speed, time saved, a GitHub-style activity heatmap and milestones |
| **Insights** | Daily word goal, filler words (click one to auto-remove it), speaking-speed trend, time of day, and your catchphrases |
| **History & stats** | Searchable history, auto-deleted after 15 days (you can change this). Stats are kept forever |
| **Optional account** | Back up your stats and settings (never your text or audio) so they survive a reinstall |
| **Bring your own model** | Use a local [whisper.cpp](https://github.com/ggml-org/whisper.cpp) server for speech, or [Ollama](https://ollama.com) / LM Studio for clean-up |
| **Auto-updates** | Installs new releases in the background, between dictations |
| **25 languages** | English, Hindi, Spanish, French, German, Japanese, Chinese, Tamil, Telugu, Bengali, Marathi and more |

## Privacy

- Speech-to-text runs on your Mac, with **Whisper Turbo** (whisper.cpp) or Apple's **SpeechAnalyzer**. Audio is never
  uploaded or saved.
- AI corrections and Command Mode use Apple's on-device **Foundation Models**.
- There's no analytics or telemetry. FreeFlow only goes online to:
  - download speech models once (Whisper Turbo from Hugging Face, language assets from Apple)
  - check GitHub for updates (turn this off in Settings → Updates)
  - back up to your account, only if you sign in. Backups go to the FreeFlow website's API.
- **Account backup is optional.** It stores your name, email, a hashed password, aggregate stats (word counts,
  streak, activity, filler counts, goal) and your Dictionary and Snippets. Never dictated text or audio. Backups run
  in the background a few minutes after you dictate and never slow down dictation. You can delete the account and
  its data any time from the Account screen.
- Your history is stored at `~/Library/Application Support/FreeFlow/history.json` and is deleted automatically after
  15 days (Settings → Privacy & storage).

Full details: [freeflow-voice.vercel.app/privacy](https://freeflow-voice.vercel.app/privacy).

Want different models? In Settings you can point FreeFlow at a local
[whisper.cpp](https://github.com/ggml-org/whisper.cpp) server or a local LLM through
[Ollama](https://ollama.com) or LM Studio. If you do, your audio or text goes to the server you chose.

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

More help: menu-bar icon → **Help & Troubleshooting**, the [install guide](https://freeflow-voice.vercel.app/install#troubleshooting),
or [open an issue](https://github.com/gaurav-sunthwal/freeflow/issues).

## How it works

```
hold fn ──► CGEventTap ──► AVAudioEngine ──► Whisper Turbo or SpeechAnalyzer (on-device, streamed live)
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
| `Sources/FreeFlow/WhisperEngine.swift` | On-device Whisper Turbo (whisper.cpp + Metal), transcribing while you speak |
| `Sources/FreeFlow/TextProcessor.swift` | Rules, snippets, dictionary, self-corrections, LLM safety checks |
| `Sources/FreeFlow/TextInserter.swift` | Clipboard-safe paste and selected-text capture |
| `Sources/FreeFlow/Overlay.swift` | The floating "Flow bar" |
| `Sources/FreeFlow/MainView.swift` | Home, Dictionary, Snippets, Style, Settings, Setup |
| `Sources/FreeFlow/DashboardView.swift`, `InsightsView.swift` | Home dashboard and Insights |
| `Sources/FreeFlow/Account.swift` | Optional account and background stats backup |
| `Sources/FreeFlow/Updater.swift` | Self-updates from GitHub releases |
| `Sources/FreeFlow/Links.swift` | Website, help and GitHub links used in the app |

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

Website: [freeflow-voice.vercel.app](https://freeflow-voice.vercel.app)
