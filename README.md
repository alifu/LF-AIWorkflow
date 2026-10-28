# LF-AIWorkflow

A macOS notch app that runs a small, token-saving AI coding workflow on top of the Claude Code CLI:

**Plan → Code → Test → Fix → Review**

- **Plan** and **Review** use [ECC](https://github.com/affaan-m/ECC) (`/ecc:plan`, `/ecc:code-review`).
- **Code** and **Fix** use [Graphify](https://pypi.org/project/graphifyy/) so Claude reads only the relevant part of the codebase.
- Tests run automatically after Code; only the error lines go back to Claude.
- **Research mode**: capture or crawl pages from Safari, then ask Claude to analyze or compare the data. You get a comparison table with sources.
- Work happens in a separate git worktree. The app never pushes or merges.

> Status: in development. The plan is in `.claude/plans/lf-aiworkflow.plan.md`.

---

## Requirements

| | Minimum |
|---|---|
| macOS | 14.0 (Sonoma) or later |
| Mac | Apple Silicon recommended. Works with or without a notch (no notch → half-circle at the top of the screen) |
| Claude | A Claude account that can use Claude Code (Pro, Max, Team or API key) |

## Dependencies

LF-AIWorkflow does **not** bundle these tools. It finds them on your `PATH` (and in `/opt/homebrew/bin`, `~/.local/bin`). You can set custom paths in **Settings → Tools**.

### Required

| Tool | Used for | Install | Check |
|---|---|---|---|
| [Homebrew](https://brew.sh) | Installing the app and tools | `/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"` | `brew --version` |
| Git | Diffs, branches, worktrees | `xcode-select --install` (or `brew install git`) | `git --version` |
| [Claude Code CLI](https://docs.claude.com/en/docs/claude-code) | All AI stages, run as a terminal session | `curl -fsSL https://claude.ai/install.sh \| bash`, then run `claude` once to log in | `claude --version` |
| [ECC](https://github.com/affaan-m/ECC) (Claude Code plugin) | Plan and Review stages | In Claude Code: `/plugin marketplace add affaan-m/ECC`, then `/plugin install ecc@ecc` | `/ecc:plan` shows up in Claude Code |
| [uv](https://docs.astral.sh/uv/) | Installing Graphify | `brew install uv` | `uv --version` |
| [Graphify](https://pypi.org/project/graphifyy/) | Code and Fix context (smaller prompts) | `uv tool install graphifyy`, then `graphify install --platform claude` | `graphify --help` |

Tested with Claude Code 2.1.311 and Graphify 0.9.32.

### Per project (for the automatic Test stage)

Install only what your projects use. The app picks the first match in the project root:

| Project has | Test command | Needs |
|---|---|---|
| `scripts/check.sh` | `./scripts/check.sh` | Whatever the script uses |
| `gradlew` (Android / KMP / CMP) | `./gradlew check` | JDK 17+ (arm64): `brew install openjdk@17`; Android SDK via Android Studio: `brew install --cask android-studio` |
| `*.xcodeproj` / `*.xcworkspace` | `xcodebuild test …` | Xcode (App Store), then `sudo xcodebuild -license accept` |
| `Package.swift` | `swift test` | Xcode or Swift toolchain |
| `package.json` | `npm test` | `brew install node` |
| `Cargo.toml` | `cargo test` | `brew install rust` |
| `go.mod` | `go test ./...` | `brew install go` |
| `Makefile` | `make test` | Xcode Command Line Tools |

You can override the command for each project in **Settings → Projects**.

### For Research mode (Safari)

Research mode reads the Safari tabs you choose, cleans them, and asks Claude to analyze or compare the data. One-time setup:

1. Safari → **Settings → Advanced** → turn on **Show features for web developers**.
2. Safari → **Settings → Developer** → turn on **Allow JavaScript from Apple Events**.
3. The first time you capture a tab, macOS asks to let LF-AIWorkflow control Safari. Click **Allow** (or later: **System Settings → Privacy & Security → Automation → LF-AIWorkflow → Safari**).

Without these, Research mode can still crawl public URLs, but can't read your open Safari tabs. Research files are saved in `~/Documents/LF-AIWorkflow/Research/`.

### Recommended project setup

- A short `CLAUDE.md` or `AGENTS.md` (about 1 page) in the project root. It is sent on every run, so the app warns when it is missing or too long.
- A Graphify graph, built once without using tokens: `graphify update .` (creates `graphify-out/`). Keep it up to date with `graphify hook install`.
- Optional review checklist at `review/checklist-<name>.md`. It is sent to the Review stage with the diff.
- Add `graphify-out/` and `.claude/` to `.gitignore` if you don't want them committed.

### One-shot install of the required tools

```bash
xcode-select --install
brew install uv
curl -fsSL https://claude.ai/install.sh | bash
uv tool install graphifyy && graphify install --platform claude
claude   # log in, then run:
         #   /plugin marketplace add affaan-m/ECC
         #   /plugin install ecc@ecc
```

---

## Install

Not released yet. When it is:

```bash
brew tap alifu/lf-aiworkflow
brew install --cask lf-aiworkflow
```

The app is not notarized by Apple. The cask removes the quarantine flag on install. If macOS still blocks the app:

```bash
xattr -dr com.apple.quarantine /Applications/LF-AIWorkflow.app
```

## Build from source

Requires Xcode 26.5 or later (Swift 6 language mode).

```bash
git clone https://github.com/alifu/LF-AIWorkflow.git
cd LF-AIWorkflow
xcodebuild -project LF-AIWorkflow.xcodeproj -scheme LF-AIWorkflow -destination 'platform=macOS' build
```

Run the tests:

```bash
xcodebuild -project LF-AIWorkflow.xcodeproj -scheme LF-AIWorkflow -destination 'platform=macOS' test
```
