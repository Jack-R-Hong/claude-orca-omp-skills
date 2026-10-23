---
name: orca-omp-doctor
description: Checks the orca-omp orchestration setup - Claude Code, the Orca runtime, the omp agent, worker models, whether the local model is really local, and skill installation. Use when the user says /orca-omp-doctor, "check omp setup", "orca-omp is broken" (「檢查 omp 設定」), or when a /orca-omp prerequisite step fails.
---

# orca-omp setup check

Report to the user in the language they use.

1. Run the check script (it never prints keys):
   ```bash
   bash ~/.claude/skills/orca-omp-doctor/scripts/doctor.sh
   ```
   Add `--live` when the user asks to test the models, or when all basic checks pass but workers still fail. It sends each worker model `Reply with exactly: OK`, up to 2 minutes per model.
2. Report the results: FAIL items first, then WARN, each with the script's `→` fix hint. If everything passes, say in one sentence that `/orca-omp` is ready.
3. If a fix means changing config or starting a service (for example `orca open`, or editing `~/.omp/agent/models.yml`), explain what you will do and ask first. For interactive commands such as `omp login`, ask the user to run them with `! <command>`.
4. After fixing, rerun the script to confirm.

## What it checks
| Section | Checks |
|---|---|
| Commands | `claude`, `orca`, `omp`, `git`, `python3`, `curl` are on PATH |
| Orca | runtime is ready; agent id `omp` is accepted; the orchestration guide is available; whether we are inside an Orca terminal (otherwise the coordinator is not shown in Orca) |
| omp models | `ORCA_OMP_MODEL` and `ORCA_OMP_LOCAL_MODEL` both appear in `omp models` |
| Local model stays local | the local model provider's `baseUrl` points at localhost and the server responds |
| Skills installed | both skills are in `~/.claude/skills/` |
