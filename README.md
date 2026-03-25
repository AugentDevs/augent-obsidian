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
  <a href="https://opensource.org/licenses/MIT"><img src="https://img.shields.io/badge/License-MIT-blue.svg?style=for-the-badge" alt="License: MIT"></a>
  <img src="https://img.shields.io/badge/platform-macOS-lightgrey.svg?style=for-the-badge" alt="macOS only">
  <img src="https://img.shields.io/badge/telemetry-none-green.svg?style=for-the-badge" alt="No Telemetry">
  <img src="https://img.shields.io/badge/dependencies-python3%20%2B%20curl-orange.svg?style=for-the-badge" alt="Dependencies">
</p>

<p align="center">
  <a href="#the-problem">Problem</a> ·
  <a href="#what-it-does">What It Does</a> ·
  <a href="#setup">Setup</a> ·
  <a href="#how-it-works">How It Works</a> ·
  <a href="#troubleshooting">Troubleshooting</a> ·
  <a href="#uninstall">Uninstall</a> ·
  <a href="https://docs.augent.app/guides/obsidian-setup">Docs</a>
</p>

---

## The Problem

Claude Code and Codex can already edit files inside your Obsidian vault. The bottleneck is macOS: it prevents you from setting Obsidian as the default opener for `.txt` and `.md` files.

**The problems:**
- **macOS prevents setting Obsidian as the default opener** for `.txt` and `.md` files
- **Files outside your vault** don't show up in Obsidian at all
- **External edits** from Claude or Codex can go stale without a background watcher

**What this setup fixes:**
- **Every `.txt` and `.md`** on your Mac opens directly in Obsidian
- **External files** are hard-linked into your vault automatically
- **A background service** keeps everything in sync and auto-restarts if it stops

## Security and Privacy

> **Everything runs locally. Nothing leaves your machine.**
>
> - No network requests leave localhost. Zero telemetry, zero analytics, zero tracking.
> - All source code is in this repository. The setup script compiles from source on your machine.
> - You can and should read `setup.sh` before running it. It is written to be auditable.
> - Full uninstall available -- `bash uninstall.sh` cleanly removes everything.

## What Gets Installed

| Component | Purpose | Location |
|---|---|---|
| Open in Obsidian.app | Default macOS handler for `.txt` and `.md` files | `/Applications/` |
| Obsidian File Watcher.app | Re-links external files when hard links break | `/Applications/` |
| duti config | Sets default file handler | System preference (via duti) |

## Obsidian Plugins

| Plugin | Required | Why |
|---|---|---|
| **Custom File Extensions** by MeepTech | Yes | Renders `.txt` files as markdown inside Obsidian. Without it, `.txt` files open but display as raw text with no formatting. |
| **Local REST API** by Adam Coddington | Recommended | Gives scripts and agents a REST interface to search your vault, read notes, execute commands, and make targeted edits. Not required for the core setup, but valuable for power users building automations on top of their vault. |

## Prerequisites

- macOS (Apple Silicon or Intel)
- [Obsidian](https://obsidian.md) installed with at least one vault

## Setup

### Part 1: Configure Obsidian (2 minutes, manual)

Do this **before** running the setup script.

1. Open Obsidian Settings (gear icon) > **Community plugins** > Turn on community plugins.
2. Install and enable **Custom File Extensions** by MeepTech.
   `obsidian://show-plugin?id=obsidian-custom-file-extensions-plugin`
3. *(Recommended)* Install and enable **Local REST API** by Adam Coddington.
   `obsidian://show-plugin?id=obsidian-local-rest-api`

The screenshot shows both plugins installed and enabled. Custom File Extensions is required. Local REST API is recommended for power users (adds search, read, and automation capabilities to your vault) but not necessary for the core setup:

<p align="center">
  <img src="./images/plugins.png" width="700" alt="Community plugins: Custom File Extensions and Local REST API installed and enabled">
</p>

4. Go to Settings > **Files & Links** > toggle **Detect all file extensions** ON.

<p align="center">
  <img src="./images/file-extensions.png" width="700" alt="Files & Links: Detect all file extensions toggled ON">
</p>

5. Restart Obsidian (quit fully and reopen).

### Part 2: Run the setup script

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

The script will:

- Detect your vault path automatically
- Verify the required Obsidian plugin is installed
- Compile two macOS apps from source (Swift)
- Register them as default file handlers
- Verify everything works

## How It Works

### The apps

**Open in Obsidian** -- A native Swift binary that receives Apple Events when you double-click a `.txt` or `.md` file. Files inside the vault open directly. Files outside the vault are hard-linked into an `External Files/` folder so Obsidian can index them. Falls back to symlinks for cross-volume files.

**Obsidian File Watcher** -- A background app that monitors the hard-link map every 2 seconds. When an external editor does an atomic write (creating a new inode), the hard link breaks. The watcher detects the mismatch and re-creates the link so Obsidian sees the updated content.

### Claude Code editing vault files

Claude Code's Edit tool writes directly to disk. Obsidian's file watcher detects the change and updates the note in real time. No hooks, no plugins, no sync layer required. It just works.

## Troubleshooting

| Problem | Fix |
|---|---|
| "Operation not permitted" error on open | Grant Full Disk Access to both apps: System Settings > Privacy & Security > Full Disk Access. Add Open in Obsidian.app and Obsidian File Watcher.app. |
| `duti -x txt` still shows TextEdit | Re-run: `bash setup.sh` (safe to run multiple times). May need logout/login. |
| swiftc fails | Run `sudo xcode-select --reset` then re-run setup. |
| Permission dialogs on Desktop/Documents | Click Allow. Both Obsidian and the apps may need filesystem access. |
| `.txt` files show raw text in Obsidian | Make sure Custom File Extensions plugin is installed and enabled. |
| External files don't appear in vault | Check that Obsidian File Watcher is running: `ps aux | grep obsidian-file-watcher` |
| Edits from Claude/Codex don't appear in Obsidian | The File Watcher may not be running. Check: `ps aux | grep obsidian-file-watcher`. If not running, re-run `bash setup.sh` to install the launchd agent that auto-starts and auto-restarts the watcher. |

## Uninstall

```bash
curl -fsSL https://augent.app/obsidian-uninstall.sh | bash
```

Or if you still have the cloned repo, run `bash uninstall.sh` from inside it.

**This removes:**

- Both apps from `/Applications/`
- File handler registrations (restores TextEdit for `.txt`, Obsidian for `.md`)
- File Watcher from login items

**This does NOT touch:**

- Your Obsidian vault or any files in it
- Your Obsidian plugins or settings
- Homebrew or duti

## Augent + Obsidian + Claude

When paired with [Augent](https://github.com/AugentDevs/Augent), your Obsidian vault becomes a living audio knowledge graph. Every podcast, interview, lecture, and tutorial you transcribe automatically becomes a connected node with semantic tags, wikilinks, and topic clusters.

**A live knowledge graph that grows with every transcription**

<p align="center">
  <img src="./images/obsidian-graph-hero.png" width="700" alt="Augent knowledge graph in Obsidian">
</p>

**Color-coded topic clusters**

<p align="center">
  <img src="./images/obsidian-graph-colored.png" width="700" alt="Obsidian graph with color-coded topic clusters">
</p>

**Local graph showing second-degree connections**

<p align="center">
  <img src="./images/obsidian-graph-small.png" width="500" alt="Graph view showing topic clusters">
</p>

---

## Used with Augent

This setup is part of the [Augent](https://github.com/AugentDevs/Augent) ecosystem -- an audio intelligence engine for Claude Code. Augent's `take_notes` tool saves rich notes as `.txt` files styled for Obsidian. This setup ensures those files open correctly in Obsidian by default.

You don't need Augent to use this repo. It works with any Obsidian vault.

## License

MIT License. See [LICENSE](LICENSE).
