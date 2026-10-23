# Install guide for AI agents

This file is written for an AI coding agent (for example Claude Code) asked to install these skills for a user. Follow it in order. Humans: see [README.md](README.md).


You are installing three Claude Code skills (`orca-omp`, `orca-omp-doctor`, `orca-omp-setup`) on the user's machine. Work through the steps in order, run each command yourself, and report what happened at the end.

## Rules
- Do not install, upgrade, or log in to any application (Claude Code, Orca, omp) without asking the user first. Interactive logins such as `omp login` must be run by the user (in Claude Code: `! omp login`).
- Do not edit `~/.omp/agent/models.yml`, API keys, or any credential file. Never print API keys or header values.
- Do not choose worker models on the user's behalf. Ask them.
- Do not pick an `anthropic/...` model without telling the user that using a Claude subscription login in third-party tools may violate Anthropic's terms.
- The settings file `~/.config/orca-omp/config.env` is personal. Never commit it or copy it into the repo.

## Step 1: Check prerequisites
```bash
for c in claude orca omp git python3 curl; do command -v "$c" >/dev/null && echo "ok $c" || echo "MISSING $c"; done
```
If anything is `MISSING`, stop and tell the user what to install:
- `orca`: Orca.app from https://github.com/stablyai/orca (the `orca` CLI comes with it)
- `omp`: https://github.com/can1357/oh-my-pi
- `claude`: https://claude.com/claude-code

## Step 2: Get the repo
```bash
REPO="$HOME/Developer/claude-orca-omp-skills"   # ask the user if they prefer another location
if [ -d "$REPO/.git" ]; then git -C "$REPO" pull --ff-only; else git clone https://github.com/Jack-R-Hong/claude-orca-omp-skills.git "$REPO"; fi
```

## Step 3: Install the skills
```bash
"$REPO/install.sh"
```
It symlinks each `skills/*` folder into `~/.claude/skills/` (override with `CLAUDE_SKILLS_DIR`). It never overwrites an existing folder that is not a symlink; it prints `skip <name>` instead. If you see a skip, show it to the user and ask before moving the existing folder.

## Step 4: Configure worker models
```bash
C="$HOME/.claude/skills/orca-omp-setup/scripts/config.sh"
bash "$C" show      # current values; models are unset on a fresh install
bash "$C" models    # omp models, each marked local or remote
```
Ask the user (one question per setting):
1. `ORCA_OMP_MODEL`: the model for general coding tasks. Any listed model.
2. `ORCA_OMP_LOCAL_MODEL`: the model for sensitive tasks. Offer only models marked `local`. If none exist, tell the user and leave it unset; sensitive tasks will then not be dispatched.

Save each answer, and show the user any error `set` prints:
```bash
bash "$C" set ORCA_OMP_MODEL "<provider/model>"
bash "$C" set ORCA_OMP_LOCAL_MODEL "<provider/model>"
```
`set` validates the value: the model must be listed by omp, and the local model must be served on localhost. Keep the defaults for `ORCA_OMP_KEEP_WORKERS`, `ORCA_OMP_WAIT_MINUTES`, and `ORCA_OMP_MAX_LOCAL_WORKERS` unless the user asks to change them. If `omp models` lists nothing usable, the user must first add a provider to omp; stop and tell them.

## Step 5: Verify
```bash
bash "$HOME/.claude/skills/orca-omp-doctor/scripts/doctor.sh"
```
- `Result: 0 failed` means the install worked. The warning `not inside an Orca terminal` is expected when you are not running inside Orca.
- For each `FAIL`, report it to the user with the `→` hint the script prints. If `Orca runtime` fails, ask the user before running `orca open`.
- Optional, only if the user agrees (sends a short prompt to each model, up to 2 minutes each): `doctor.sh --live`.

## Step 6: Report to the user
Tell the user:
1. Which skills were linked, and any that were skipped.
2. The saved models (`bash "$C" show`).
3. The doctor result.
4. How to use it: start Claude Code inside an Orca terminal (see [Start Claude Code as the coordinator from inside Orca](https://github.com/Jack-R-Hong/claude-orca-omp-skills#start-claude-code-as-the-coordinator-from-inside-orca)), then `/orca-omp <task>`. If the new skills do not appear in the current Claude Code session, start a new session.

## Uninstall
```bash
for s in orca-omp orca-omp-doctor orca-omp-setup; do [ -L "$HOME/.claude/skills/$s" ] && rm "$HOME/.claude/skills/$s"; done
rm -r "$HOME/.config/orca-omp"    # personal settings; ask the user first
```
