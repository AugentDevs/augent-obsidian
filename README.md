# augent-obsidian

<p align="center">
  <picture>
    <img src="./images/banner.png" width="600" alt="Augent + Obsidian">
  </picture>
</p>

<p align="center">
  <strong>Obsidian as your default editor for every .txt and .md file, with live sync for agent edits.</strong>
</p>

<p align="center">
  <a href="https://github.com/AugentDevs/augent-obsidian/actions/workflows/ci.yml"><img src="https://img.shields.io/github/actions/workflow/status/AugentDevs/augent-obsidian/ci.yml?style=for-the-badge&label=CI" alt="CI"></a>
  <a href="https://opensource.org/licenses/MIT"><img src="https://img.shields.io/badge/License-MIT-blue.svg?style=for-the-badge" alt="License: MIT"></a>
  <img src="https://img.shields.io/badge/macOS_13+-lightgrey.svg?style=for-the-badge" alt="macOS 13+">
  <img src="https://img.shields.io/badge/telemetry-none-green.svg?style=for-the-badge" alt="No Telemetry">
</p>

<p align="center">
  <a href="#the-problem">Problem</a> &middot;
  <a href="#setup">Setup</a> &middot;
  <a href="#how-it-works">How It Works</a> &middot;
  <a href="#troubleshooting">Troubleshooting</a> &middot;
  <a href="#uninstall">Uninstall</a> &middot;
  <a href="https://docs.augent.app/guides/obsidian-setup">Docs</a>
</p>

---

## The Problem

macOS prevents setting Obsidian as the default opener for `.txt` and `.md` files. Files outside your vault don't show up in Obsidian. External edits from Claude Code or Codex can go stale without a background watcher.

**This setup fixes all three:**

- Every `.txt` and `.md` on your Mac opens directly in Obsidian
- External files are hard-linked into your vault automatically
- A background service keeps everything in sync and auto-restarts if it stops

## Security

> **Everything runs locally. Nothing leaves your machine.**
>
> No network requests, no telemetry, no analytics. Source code compiles from this repository on your machine. Read `setup.sh` before running it. Full uninstall with `bash uninstall.sh`.

## Setup

### 1. Configure Obsidian

Do this **before** running the setup script.

1. Settings > **Community plugins** > Turn on community plugins
2. Install and enable **Custom File Extensions** by MeepTech
3. *(Recommended)* Install and enable **Local REST API** by Adam Coddington
4. Settings > **Files & Links** > toggle **Detect all file extensions** ON
5. Restart Obsidian (quit fully and reopen)

<p align="center">
  <img src="./images/plugins.png" width="700" alt="Community plugins: Custom File Extensions and Local REST API installed and enabled">
</p>

<p align="center">
  <img src="./images/file-extensions.png" width="700" alt="Files & Links: Detect all file extensions toggled ON">
</p>

### 2. Install

**One-liner (recommended)**

```bash
curl -fsSL https://augent.app/obsidian.sh | bash
```

**Or clone and run**

```bash
git clone https://github.com/AugentDevs/augent-obsidian.git
cd augent-obsidian
bash setup.sh
```

The script detects your vault, verifies the required plugin, compiles two native macOS apps from source, registers file handlers, and starts a background service.

### What gets installed

| Component | Purpose | Location |
|:----------|:--------|:---------|
| Open in Obsidian.app | Default macOS handler for `.txt` and `.md` | `/Applications/` |
| Obsidian File Watcher.app | Re-links external files when hard links break | `/Applications/` |
| LaunchAgent | Auto-starts and auto-restarts the File Watcher | `~/Library/LaunchAgents/` |

### Required plugins

| Plugin | Required | Why |
|:-------|:---------|:----|
| **Custom File Extensions** (MeepTech) | Yes | Renders `.txt` files as markdown inside Obsidian |
| **Local REST API** (Adam Coddington) | Recommended | REST interface for vault search, reads, and automation |

## How It Works

**Open in Obsidian** receives Apple Events when you double-click a `.txt` or `.md` file. Files inside the vault open directly. Files outside the vault are hard-linked into `External Files/` so Obsidian can index them. Falls back to symlinks for cross-volume files.

**Obsidian File Watcher** monitors the hard-link map every 2 seconds. When an external editor does an atomic write (new inode), the hard link breaks. The watcher detects the mismatch and re-creates it so Obsidian sees the updated content.

**Claude Code** writes directly to disk. Obsidian detects the change and updates the note in real time. No hooks, no plugins, no sync layer.

## Troubleshooting

| Problem | Fix |
|:--------|:----|
| "Operation not permitted" on open | System Settings > Privacy & Security > Full Disk Access. Add both apps. |
| `duti -x txt` still shows TextEdit | Re-run `bash setup.sh` (safe to repeat). May need logout/login. |
| `swiftc` fails | `sudo xcode-select --reset` then re-run setup. |
| `.txt` files show raw text | Enable Custom File Extensions plugin in Obsidian. |
| External files missing from vault | Check watcher is running: `ps aux \| grep obsidian-file-watcher` |
| Claude edits don't appear | Same as above. Re-run `bash setup.sh` to reinstall the LaunchAgent. |
| Repeated "Error editing file" across panes | Two Claude Code panes editing the same file. Pane 2's context goes stale after Pane 1 edits. Tell Claude to re-read the file before editing. |

## Uninstall

```bash
curl -fsSL https://augent.app/obsidian-uninstall.sh | bash
```

Or from a local clone: `bash uninstall.sh`

**Removes:** both apps, file handler registrations, LaunchAgent.
**Does not touch:** your vault, plugins, settings, Homebrew, or duti.

## Augent + Obsidian

When paired with [Augent](https://github.com/AugentDevs/Augent), your vault becomes a living knowledge graph. Every transcription becomes a connected node with semantic tags, wikilinks, and topic clusters. Augent's `take_notes` and `visual` tools save notes and screenshots as `.md` and `.png` files. This setup ensures they open correctly in Obsidian by default.

You don't need Augent to use this repo. It works with any Obsidian vault.

<p align="center">
  <img src="./images/obsidian-graph-hero.png" width="700" alt="Augent knowledge graph in Obsidian">
</p>

<p align="center">
  <img src="./images/obsidian-graph-colored.png" width="700" alt="Obsidian graph with color-coded topic clusters">
</p>

<p align="center">
  <img src="./images/obsidian-graph-small.png" width="500" alt="Local graph showing second-degree connections">
</p>

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

MIT. See [LICENSE](LICENSE).
