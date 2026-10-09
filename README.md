<p align="center">
  <img src="docs/assets/app-icon.png" width="128" alt="SkillsPack icon" />
</p>
<h1 align="center">SkillsPack</h1>
<h3 align="center">Every agent skill on your Mac, in one menu bar.</h3>

<p align="center">
  <img src="https://img.shields.io/badge/Swift-6-orange.svg" />
  <img src="https://img.shields.io/badge/macOS-14+-blue.svg" />
  <img src="https://img.shields.io/badge/Apple%20Silicon-arm64-lightgrey.svg" />
  <img src="https://github.com/InsaneArts/SkillsPack/actions/workflows/ci.yml/badge.svg" />
</p>

<p align="center">
  <img src="docs/assets/showreel.gif" width="90%" alt="SkillsPack opens from the menu bar, turns every skill off and back on, then opens a skill to switch it per agent" />
</p>

Claude Code, Codex and pi each keep their own skills in their own folders, with their own way to
turn one off. SkillsPack reads all of them and shows them in one list: which agents have each
skill, whether it is on, and how often you and your agents used it.

It changes nothing it does not have to. Turning a skill off writes the agent's own setting, so
files never move, and every config file is backed up before SkillsPack touches it.

## See every skill

The list shows each skill with three dots, one per agent: filled when it is on, a ring when it is
off, faint when that agent does not have it. Skills are ranked by how often they were used in the
last 90 days, counted from the agents' session logs, split into uses by you and uses by the agent.
Search, filter by agent, or show only skills that are off, never used, or have an update.

Open a skill to read its `SKILL.md`, see where each agent keeps it, and turn it on or off with a
switch per agent.

<p align="center">
  <img src="docs/assets/list.png" width="30%" alt="The skill list with usage counts and per-agent dots" />
  <img src="docs/assets/detail.png" width="30%" alt="A skill's page with a switch for Claude, Codex and pi" />
  <img src="docs/assets/health.png" width="30%" alt="Health: a broken link, the context each agent loads, and skills unused for 90 days" />
</p>

## Turn skills on and off

| Agent | Skill folders it reads | Switch SkillsPack writes |
|---|---|---|
| Claude Code | `~/.claude/skills`, Claude plugins | `"skillOverrides": {"<name>": "off"}` in `~/.claude/settings.json` |
| Codex | `~/.codex/skills`, `~/.agents/skills` | `[[skills.config]]` with `name` and `enabled = false` in `~/.codex/config.toml` |
| pi | `~/.pi/agent/skills`, `~/.agents/skills` | `"-<path>/SKILL.md"` in the `skills` array of `~/.pi/agent/settings.json` |

Turning a skill back on removes the entry, so the file returns to exactly what it was. SkillsPack
keeps the key order and formatting of these files. **Turn All Off** switches off every skill for
the selected agents in one write per file; **Turn All On** restores exactly the ones it changed.

A dashed agent on a skill means that agent does not have it. One click copies it there.

## Fix what is broken

Health finds broken symlinks, skills sitting in a folder no agent reads (such as `~/.pi/skills`)
and copies of one skill that differ between agents, and fixes each with one click.

It also shows what your skills cost: every agent loads the name and description of each skill
that is on, in every session. SkillsPack estimates the tokens per agent and lists the skills you
have not used in 90 days, with a button to turn them off.

## Add skills from a URL

Paste `owner/repo`, a GitHub link to a repository or to one skill's folder, or any git URL.
SkillsPack clones it, lists the skills inside, and copies the ones you pick into each agent's
folder. It records where each skill came from, so **Check Skills for Updates** can compare your
copy with the source. Skills installed with `npx skills` keep their source too, and skills from
Claude plugins update through `claude plugin update`.

Skills with no known source can be matched by name against repositories you add in Health.

## Install

With Homebrew:

```sh
brew install --cask tornikegomareli/tap/skillspack
```

Or with one line, which downloads the latest notarized release, checks it with Gatekeeper and
copies it to /Applications:

```sh
curl -fsSL https://raw.githubusercontent.com/InsaneArts/SkillsPack/main/install.sh | bash
```

Or grab [**SkillsPack.dmg**](https://github.com/InsaneArts/SkillsPack/releases/latest/download/SkillsPack.dmg)
from the latest release.

Requirements: macOS 14 or newer on Apple Silicon. SkillsPack needs no permissions; it reads and
writes files in your home folder.

Updates arrive through the app. It checks once a day, and every update is verified against an
EdDSA signature before it installs. The menu's **Check for SkillsPack Updates…** checks now.

## Remove

```sh
brew uninstall --cask skillspack                                   # if installed with Homebrew
curl -fsSL https://raw.githubusercontent.com/InsaneArts/SkillsPack/main/install.sh | bash -s -- --uninstall
```

Or quit SkillsPack and drag it to the Trash. Your agents' skills and settings stay as they are.
SkillsPack's own data in `~/Library/Application Support/SkillsPack` stays too; delete it for a
clean slate.

## Files

SkillsPack keeps its own data in `~/Library/Application Support/SkillsPack`:

- `sources.json`: where each installed skill came from.
- `repos.json`: the repositories used to match sources.
- `turned-off.json`: what **Turn All Off** changed, so **Turn All On** can restore it.
- `usage-cache.json`: usage counts per session log, so only new logs are read again.
- `backups/`: the 20 newest copies of each agent config file before SkillsPack changed it.

## Development

```sh
git clone https://github.com/InsaneArts/SkillsPack.git
cd SkillsPack
swift build
swift test
Scripts/run.sh       # package build/SkillsPack.app and open it
```

`Scripts/package_app.sh` signs with the certificate in `APP_IDENTITY` when it is in your keychain
and ad-hoc otherwise. `Scripts/make_icon.sh` redraws the app icon from `Scripts/make_icon.swift`.

Releases are cut with `Scripts/release.sh <version>`: it tests, builds, signs with Developer ID,
notarizes a DMG, signs the Sparkle update, regenerates `appcast.xml`, updates the cask and the
public tap, and publishes the GitHub release. `Scripts/setup-sparkle-keys.sh` manages the
update-signing key.

The demo film in [`films/skillspack-demo`](films/skillspack-demo) is rendered from real SkillsPack
screens; its brief, shot list and reviews are in the same folder.

## License

[MIT](LICENSE)
