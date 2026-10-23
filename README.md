# claude-orca-omp-skills

**English** | [繁體中文](README.zh-TW.md)

Claude Code skills that make Claude Code (Opus) the coordinator of an [Orca](https://github.com/stablyai/orca) orchestration run. Opus dispatches coding subtasks to [oh-my-pi](https://github.com/can1357/oh-my-pi) (`omp`) workers and verifies the results. Sensitive tasks go to a model running on your own machine, so that data never leaves it.

| Skill | Command | Purpose |
|---|---|---|
| `orca-omp` | `/orca-omp <task>` | Decompose → dispatch omp workers → wait → verify → merge |
| `orca-omp-doctor` | `/orca-omp-doctor` | Check that the whole setup works |

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

Set the worker models (omp `provider/model` selectors; list them with `omp models`):

```bash
export ORCA_OMP_MODEL="strata/qwen3.8-flash-next-coder-iq1_m"   # general tasks
export ORCA_OMP_LOCAL_MODEL="omlx/Qwen3.8-27B-MLX-4bit"         # sensitive tasks, must be local
export ORCA_OMP_KEEP_WORKERS=1                                 # keep finished worker terminals open in Orca (0 = close them)
```

The values above are the defaults when unset (the author's own setup). Replace them with your models.

Put the `export` lines in `~/.zshrc` (or your shell profile). Orca terminals start a login shell, so that is where they are picked up.

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

## License

MIT
