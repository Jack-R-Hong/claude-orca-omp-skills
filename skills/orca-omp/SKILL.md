---
name: orca-omp
description: Orchestration mode. Claude Code (Opus) acts as the Orca orchestration coordinator, breaks work into tasks, dispatches coding subtasks to oh-my-pi (omp) workers, routes sensitive tasks to a local model, and verifies every result. Use when the user says /orca-omp, "use omp", "dispatch to omp" (「用 omp 做」, 「派給 omp」). If setup fails, run /orca-omp-doctor first.
---

# Opus orchestration + Orca + omp workers

You (Opus) are the coordinator of an Orca orchestration run: read the code, split the work, dispatch, and verify. Implementation belongs to omp workers. Do not write the implementation yourself unless a task's worker has failed twice.

Report to the user in the language they use.

## Configuration
Worker models come from environment variables, with defaults when unset. Values are omp `provider/model` selectors (see `omp models`):

| Variable | Default | Used for |
|---|---|---|
| `ORCA_OMP_MODEL` | `strata/qwen3.8-flash-next-coder-iq1_m` | General tasks |
| `ORCA_OMP_LOCAL_MODEL` | `omlx/Qwen3.8-27B-MLX-4bit` | Sensitive tasks; must be served on this machine |
| `ORCA_OMP_KEEP_WORKERS` | `1` | `1`: keep settled worker terminals open in Orca (`worker-retain`) so the user can inspect omp's context. `0`: release them. |

Before starting, run `echo "${ORCA_OMP_MODEL:-strata/qwen3.8-flash-next-coder-iq1_m} ${ORCA_OMP_LOCAL_MODEL:-omlx/Qwen3.8-27B-MLX-4bit} ${ORCA_OMP_KEEP_WORKERS:-1}"` to get the actual values. `<MODEL>`, `<LOCAL_MODEL>` and `<KEEP>` below refer to them.

## 0. Prerequisites
On first use, or if any step below fails, run `/orca-omp-doctor` first.
1. Load the version-matched Orca rules and follow them throughout. They are the authority on lifecycle, ack, and release:
   `orca skills get orchestration`
2. `orca status --json`: if the runtime is not running, `orca open`.
3. `orca repo list`: if the target repo is not registered, `orca repo add --path <path>`.
4. Prefer running Claude Code inside an Orca terminal so the user sees the coordinator and all workers in one window.
5. If `echo $ORCA_TERMINAL_HANDLE` is empty (Claude Code is not in an Orca terminal), orchestration commands fail with `no_active_sender_terminal`. Create a dedicated coordinator terminal and use its handle from then on:
   `orca terminal create --worktree path:<repo> --title "coordinator (Claude Code)" --json` → take `terminal.handle` as `<H>`.
   - `run-create` and `worker-start`: add `--from <H>`; `worker-start` also takes `--run <run_id>`.
   - `check`: add `--run <run_id> --terminal <H>` (not `--from`).
   - `worker-release` accepts only `--dispatch <dispatch_id>`; do not add `--run` or `--from`.
   - Never use another pane's handle (for example a worker's).

## 1. Decompose
- Read the relevant code first, then split the work into small, independent tasks (ideally 1–3 files each).
- Assume worker models are weak (small or heavily quantized local models). Every spec must follow Orca's task-spec contract:
  **Target** (files/functions), **Change** (concrete result), **Constraints** (what must not change), **Ownership** (which files it may edit), **Observable acceptance** (the verification command).
- End every spec by reminding the worker to send `worker_done` exactly once, as its preamble instructs, with `--outcome succeeded|failed`.

## 2. Choose the worker model
Pick a route per task by sensitivity, and state which route was used in the report:

| Route | `--model` | When |
|---|---|---|
| General (default) | `<MODEL>` | Ordinary coding tasks. |
| Local | `<LOCAL_MODEL>` | Data must not leave this machine: tasks touching `.env`, keys, credentials, `~/.ssh`, personal data, unreleased code or customer data, or reading/writing local system settings or keychain scripts. |

- The local model shares this machine's memory and GPU with Orca and Claude Code. Run at most 1–2 local workers at a time.
- When unsure whether a task is sensitive, use the local route.
- The local route only keeps data on the machine. It does not make actions safer: the worker can still run commands here. Sensitive specs must list the allowed commands and files, forbid deletions, `git push`, and outbound network requests, and forbid putting secrets in the `worker_done` summary or logs.
- Verify sensitive tasks by reviewing the diff locally. Do not paste secrets anywhere except back to the user.

## 3. Dispatch
```bash
orca orchestration run-create --objective "<overall goal>" --json
# Start all independent tasks at once, each in its own child worktree
orca orchestration worker-start --spec "<spec>" --task-title "<short title>" \
  --worktree new-child --agent omp \
  --model <MODEL or LOCAL_MODEL> --json
```
- Each worker runs in its own child worktree, so in Orca its terminal sits under that worktree in the sidebar, not under the coordinator's repo. After starting the first worker, bring it to the front with `orca terminal switch --terminal <worker handle>` (the `terminal` effect in the `worker-start` result) and tell the user which worktree each worker is in.
- For ordered work, use `task-create --deps` + `worker-start --task <id>`; keep dependency chains at most 3 deep.
- OMP does not support `--effort`; do not pass it.
- If `worker-start` fails, do not simply rerun it. Read `failedStage` and load the recovery reference per the Orca rules.

## 4. Wait and verify
```bash
orca orchestration check --wait --types "worker_done,escalation,question" --timeout-ms 900000 --json
```
- Prompt cache: assume a 1-hour cache TTL (it may drop to 5 minutes when usage goes into overage). Keep each `check --wait` timeout at 15 minutes (50 at most) so every wake-up lands inside the TTL and cheaply refreshes the cache. Never wait more than 1 hour in a single call.
- Keep the coordinator context lean so a cache rebuild stays cheap: read only the parts of worker output you need (`tail`, `jq`), never pull whole terminal output or large diffs into the conversation, and condense finished tasks to a few lines before a long wait.
- On `question`, answer with `reply`. On `worker_done`:
  - Review with `orca file diff` or `git diff` in the worktree and run the acceptance command yourself. Do not trust the worker's summary alone.
  - Pass: merge into the main branch. Then, if `<KEEP>` is `1`, `worker-retain --dispatch <dispatch_id>` so the omp terminal stays open in Orca; otherwise `worker-release` (which closes the terminal).
  - Fail: re-dispatch once in the same terminal with the concrete error and how to fix it. Take over only if it fails again.
- Weak models may forget `worker_done`. After three consecutive empty waits, inspect with `worker-list` per the Orca rules; `orca terminal read` shows worker output. Do not stop or abandon a worker without positive proof.
- Before finishing, confirm `worker-list --run <run_id> --terminal-state reclaimable --json` is empty.

## 5. Report
For each task, list: outcome, evidence (test output / diff summary), worktree path, unresolved issues.
The user can watch every worker's terminal in the Orca window, under each worker's worktree. To see an omp worker's full context, run `/dump` in that worker's terminal. If the terminal was already released, reopen the session in Orca:
`orca terminal create --worktree path:<worker worktree> --title "omp session" --command "omp -r <omp session id>" --focus --json`
(find the session id with `grep -l -r <worktree path> ~/.omp/agent/sessions | xargs ls -t | head -1`), or print it with `omp render <session-id> --plain`.
Retained terminals stay until the user is done; when they ask to clean up, `worker-release` each retained dispatch.
