# claude-orca-omp-skills

**English** | [繁體中文](README.zh-TW.md)

> **AI agents:** to install these skills for a user, follow [Install guide for AI agents](#install-guide-for-ai-agents).

Claude Code skills that make Claude Code (Opus) the coordinator of an [Orca](https://github.com/stablyai/orca) orchestration run. Opus dispatches coding subtasks to [oh-my-pi](https://github.com/can1357/oh-my-pi) (`omp`) workers and verifies the results. Sensitive tasks go to a model running on your own machine, so that data never leaves it.

| Skill | Command | Purpose |
|---|---|---|
| `orca-omp` | `/orca-omp <task>` | Decompose → dispatch omp workers → wait → verify → merge |
| `orca-omp-doctor` | `/orca-omp-doctor` | Check that the whole setup works |
| `orca-omp-setup` | `/orca-omp-setup` | View and change your personal settings (models, limits) |

## How it works

1. Opus reads the code and splits the request into small tasks (Target / Change / Constraints / Ownership / Acceptance).
2. It picks a worker model per task: `ORCA_OMP_MODEL` for general tasks, `ORCA_OMP_LOCAL_MODEL` (must be local) for tasks touching keys, personal data or unreleased code.
3. `orca orchestration worker-start --agent omp --worktree new-child` dispatches tasks in parallel, one child worktree each, all visible live in the Orca window.
4. `orca orchestration check --wait` waits for `worker_done`. Opus reviews the diff and runs the tests itself, merges and calls `worker-release` on success, and re-dispatches with the error on failure.

## Requirements

- [Claude Code](https://claude.com/claude-code)
- Orca.app and the `orca` CLI
- `omp`, with providers for both worker models (one general, one local) in `~/.omp/agent/models.yml`
- `python3`, `curl`, `git`

> Use an API key or a non-Claude-subscription provider for omp. Signing a third-party tool in with a Claude subscription's OAuth may violate Anthropic's terms of use.

## Install

```bash
git clone https://github.com/Jack-R-Hong/claude-orca-omp-skills.git
cd claude-orca-omp-skills
./install.sh            # symlinks skills/* into ~/.claude/skills/
```

Then, in Claude Code, run `/orca-omp-setup`. It lists your omp models (marked local or remote), asks which to use, and saves your choices.

### Settings

Settings are personal and live outside the repo, in `~/.config/orca-omp/config.env` (override the path with `ORCA_OMP_CONFIG`). Change them with `/orca-omp-setup`, or directly:

```bash
C=~/.claude/skills/orca-omp-setup/scripts/config.sh
bash $C show                                          # current values and their source
bash $C models                                        # omp models, marked local / remote
bash $C set ORCA_OMP_MODEL <provider/model>           # validated before writing
```

| Key | Default | Meaning |
|---|---|---|
| `ORCA_OMP_MODEL` | none | omp model for general tasks |
| `ORCA_OMP_LOCAL_MODEL` | none | omp model for sensitive tasks; must be served on localhost |
| `ORCA_OMP_KEEP_WORKERS` | `1` | keep finished worker terminals open in Orca (`0` closes them) |
| `ORCA_OMP_WAIT_MINUTES` | `15` | length of each wait for workers, 1–50 |
| `ORCA_OMP_MAX_LOCAL_WORKERS` | `2` | max local-model workers at once |

An environment variable with the same name overrides the file. The file is parsed as plain `KEY=VALUE` lines and never executed.

## Start Claude Code as the coordinator from inside Orca

Claude Code must run **inside an Orca terminal** for the Opus orchestration to appear in the same Orca window as the workers. Orca sets `ORCA_TERMINAL_HANDLE` in its own terminals, and the skill uses it to identify the coordinator.

### 1. Add the project to Orca

```bash
orca open                                   # start Orca (skip if already running)
orca repo add --path ~/Developer/<repo>     # register the project (once)
```

### 2. Start Claude Code

Pick one:

**A. From the CLI (recommended)**

```bash
orca agent launch --agent claude --worktree path:$HOME/Developer/<repo> \
  --surface terminal --model opus --focus
```

`--surface terminal` runs Claude Code as a terminal rather than Orca's chat UI, which guarantees `ORCA_TERMINAL_HANDLE` is set.

**B. From the Orca UI**

Select the project in the sidebar, open a new terminal tab, and run `claude`.

**C. Continue an existing Claude Code conversation**

In an Orca terminal tab, `cd` to the directory where that conversation was started and run:

```bash
claude --resume <session-id>
```

Then quit the original Claude Code outside Orca, so two copies are not driving the same conversation.

### 3. Check and start

In the Claude Code running inside Orca:

1. `/orca-omp-doctor`: `running inside an Orca terminal` should be PASS.
2. `/orca-omp <task description>`

### What you will see in Orca

- **Under the main project:** the Claude Code (Opus) orchestration conversation.
- **Under each child worktree** (sidebar): one omp worker's terminal, showing what it is doing live.
- With `ORCA_OMP_KEEP_WORKERS=1` (default), worker terminals stay open after the task finishes, so you can run `/dump` there to see the full context omp sent to the model.

## Usage

1. Check the setup: `/orca-omp-doctor` (ask it to use `--live` to test the models).
2. Start Claude Code inside an Orca terminal as described above.
3. `/orca-omp <task description>`

It also works outside an Orca terminal: the skill creates a coordinator terminal to act as its identity, but the Opus conversation will not appear in Orca.

## Notes

- The local route only keeps data on the machine. It does not make actions safer: the worker can still run commands locally. Specs for sensitive tasks list the allowed files and commands.
- Small or heavily quantized models may forget to send `worker_done`. After three empty waits, the skill falls back to `worker-list` / `terminal read`.
- Each wait stays under 15 minutes so Claude Code's prompt cache does not expire.

## Install guide for AI agents

<!-- This section is written for an AI coding agent (for example Claude Code) asked to install these skills for a user. Follow it in order. -->

You are installing three Claude Code skills (`orca-omp`, `orca-omp-doctor`, `orca-omp-setup`) on the user's machine. Work through the steps in order, run each command yourself, and report what happened at the end.

### Rules
- Do not install, upgrade, or log in to any application (Claude Code, Orca, omp) without asking the user first. Interactive logins such as `omp login` must be run by the user (in Claude Code: `! omp login`).
- Do not edit `~/.omp/agent/models.yml`, API keys, or any credential file. Never print API keys or header values.
- Do not choose worker models on the user's behalf. Ask them.
- Do not pick an `anthropic/...` model without telling the user that using a Claude subscription login in third-party tools may violate Anthropic's terms.
- The settings file `~/.config/orca-omp/config.env` is personal. Never commit it or copy it into the repo.

### Step 1: Check prerequisites
```bash
for c in claude orca omp git python3 curl; do command -v "$c" >/dev/null && echo "ok $c" || echo "MISSING $c"; done
```
If anything is `MISSING`, stop and tell the user what to install:
- `orca`: Orca.app from https://github.com/stablyai/orca (the `orca` CLI comes with it)
- `omp`: https://github.com/can1357/oh-my-pi
- `claude`: https://claude.com/claude-code

### Step 2: Get the repo
```bash
REPO="$HOME/Developer/claude-orca-omp-skills"   # ask the user if they prefer another location
if [ -d "$REPO/.git" ]; then git -C "$REPO" pull --ff-only; else git clone https://github.com/Jack-R-Hong/claude-orca-omp-skills.git "$REPO"; fi
```

### Step 3: Install the skills
```bash
"$REPO/install.sh"
```
It symlinks each `skills/*` folder into `~/.claude/skills/` (override with `CLAUDE_SKILLS_DIR`). It never overwrites an existing folder that is not a symlink; it prints `skip <name>` instead. If you see a skip, show it to the user and ask before moving the existing folder.

### Step 4: Configure worker models
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

### Step 5: Verify
```bash
bash "$HOME/.claude/skills/orca-omp-doctor/scripts/doctor.sh"
```
- `Result: 0 failed` means the install worked. The warning `not inside an Orca terminal` is expected when you are not running inside Orca.
- For each `FAIL`, report it to the user with the `→` hint the script prints. If `Orca runtime` fails, ask the user before running `orca open`.
- Optional, only if the user agrees (sends a short prompt to each model, up to 2 minutes each): `doctor.sh --live`.

### Step 6: Report to the user
Tell the user:
1. Which skills were linked, and any that were skipped.
2. The saved models (`bash "$C" show`).
3. The doctor result.
4. How to use it: start Claude Code inside an Orca terminal (see "Start Claude Code as the coordinator from inside Orca"), then `/orca-omp <task>`. If the new skills do not appear in the current Claude Code session, start a new session.

### Uninstall
```bash
for s in orca-omp orca-omp-doctor orca-omp-setup; do [ -L "$HOME/.claude/skills/$s" ] && rm "$HOME/.claude/skills/$s"; done
rm -r "$HOME/.config/orca-omp"    # personal settings; ask the user first
```

## License

MIT
