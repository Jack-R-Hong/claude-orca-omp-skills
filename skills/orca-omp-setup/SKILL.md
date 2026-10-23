---
name: orca-omp-setup
description: View and change personal orca-omp settings - which omp model handles general tasks, which local model handles sensitive tasks, whether finished worker terminals stay open in Orca, wait length, and local worker limit. Use when the user says /orca-omp-setup, "change the omp model", "configure orca-omp" (「設定 orca-omp」, 「換 worker 模型」), on first install, or when /orca-omp-doctor reports a model is unset.
---

# orca-omp personal settings

Settings live in a personal file outside the repo (default `~/.config/orca-omp/config.env`, override with `ORCA_OMP_CONFIG`). An environment variable with the same name overrides the file. All reads and writes go through the helper; never edit the file by hand or source it:

```bash
C=~/.claude/skills/orca-omp-setup/scripts/config.sh
bash $C show                 # current values and where each comes from (env / file / default / unset)
bash $C models               # omp models, each marked local or remote
bash $C set KEY VALUE        # validates before writing
bash $C unset KEY
```

Report to the user in the language they use.

## Settings
| Key | Default | Meaning |
|---|---|---|
| `ORCA_OMP_MODEL` | none | omp selector for general coding tasks |
| `ORCA_OMP_LOCAL_MODEL` | none | omp selector for sensitive tasks; must be served on localhost |
| `ORCA_OMP_KEEP_WORKERS` | `1` | `1` keep finished worker terminals open in Orca, `0` close them |
| `ORCA_OMP_WAIT_MINUTES` | `15` | length of each `check --wait`, 1–50 (stays inside the 1-hour prompt cache TTL) |
| `ORCA_OMP_MAX_LOCAL_WORKERS` | `2` | max local-model workers running at once |

## Flow
1. Run `show`. If the user named a specific change, make only that change (step 3) and skip the questions.
2. Otherwise, run `models` and ask the user with AskUserQuestion, one question per setting that is unset or that they want to change:
   - General model: offer up to 4 listed models, recommended first. Note when a model is remote, and if its provider is `anthropic` with a Claude subscription login, warn that using a Claude subscription in third-party tools may violate Anthropic's terms.
   - Local model: offer only models marked `local`. If none exist, say so and leave it unset; sensitive tasks then cannot be dispatched.
   - Keep workers, wait minutes, local worker limit: ask only if the user wants to tune them; defaults are fine.
3. Write each answer with `set`. If it fails, show the error and ask again; do not write the file another way.
4. If `set` warns that an environment variable overrides the file, tell the user where it is probably set (`~/.zshrc` or similar) and that they should remove it for the file to take effect.
5. Run `show` again, then `bash ~/.claude/skills/orca-omp-doctor/scripts/doctor.sh` to confirm the setup works.
