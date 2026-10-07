# SkillsPack

A macOS menu bar app that manages agent skills for Claude Code, Codex, and pi.

- See every installed skill, which agents have it, and how often you and your agents used it.
- Turn a skill on or off for one agent. SkillsPack writes each agent's own setting, so files never move.
- Install skills from a URL, update them from their source, and delete them (folders go to the Trash).
- Read a skill's `SKILL.md` without leaving the menu bar.
- Health: find broken links, skills in folders no agent reads, and copies of one skill that differ, then fix them in one click.
- Context cost: see about how many tokens each agent loads every session for skill descriptions, and turn off skills you have not used in 90 days.
- Source repos: add repos once, and SkillsPack links skills with no known source to same-named skills in them, so they can update.
- Checks for updates once a day and shows the number of updates next to the menu bar icon.

## Build and run

Requires macOS 14 and Swift 6.2.

```sh
swift test
Scripts/run.sh          # builds build/SkillsPack.app and opens it
```

To keep it, copy `build/SkillsPack.app` to `/Applications`.

## How on and off work

| Agent | Skill folders it reads | Switch SkillsPack writes |
|---|---|---|
| Claude Code | `~/.claude/skills`, Claude plugins | `"skillOverrides": {"<name>": "off"}` in `~/.claude/settings.json` |
| Codex | `~/.codex/skills`, `~/.agents/skills` | `[[skills.config]]` with `name` and `enabled = false` in `~/.codex/config.toml` |
| pi | `~/.pi/agent/skills`, `~/.agents/skills` | `"-<path>/SKILL.md"` in the `skills` array of `~/.pi/agent/settings.json` |

Turning a skill back on removes the entry, so the file returns to exactly what it was. SkillsPack keeps the key order and formatting of these files, and it saves a backup before every change.

Clicking a dashed agent chip copies the skill into that agent's folder.

## Install and update

Paste any of these into Install:

- `owner/repo`
- `https://github.com/owner/repo`
- `https://github.com/owner/repo/tree/main/path/to/skill`
- any other git URL

SkillsPack clones the repo, lists the skills in it, and copies the ones you pick into each agent's folder. It records the source, so Check for updates can compare your copy with the repo. It also reads sources from `~/.agents/.skill-lock.json`, written by `npx skills`. Claude plugin skills update through `claude plugin update`.

## Usage counts

SkillsPack reads session logs and counts two kinds of use:

- **By you:** `/name` in Claude Code, `$name` in Codex, `/skill:name` in pi.
- **By the agent:** Claude's Skill tool, and Codex or pi reading the skill's `SKILL.md`.

The first count reads every log. After that, only new or changed logs are read.

## Files

SkillsPack stores its own data in `~/Library/Application Support/SkillsPack`:

- `sources.json`: where each installed skill came from.
- `repos.json`: the repos used to match sources.
- `usage-cache.json`: usage counts per log file.
- `backups/`: the 20 newest copies of each agent config file before SkillsPack changed it.
