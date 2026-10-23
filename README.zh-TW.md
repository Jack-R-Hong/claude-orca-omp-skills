# claude-orca-omp-skills

[English](README.md) | **繁體中文**

> **AI agent：** 要替使用者安裝這些 skill，請照 [Install guide for AI agents](#install-guide-for-ai-agents) 的步驟。

Claude Code skills：讓 Claude Code（Opus）當 [Orca](https://github.com/stablyai/orca) orchestration 的 coordinator，把 coding 子任務派給 [oh-my-pi](https://github.com/can1357/oh-my-pi)（`omp`）worker 執行，最後由 Opus 驗收。機密任務會改派給跑在本機的模型，資料不離開這台機器。

| Skill | 指令 | 用途 |
|---|---|---|
| `orca-omp` | `/orca-omp <任務>` | 拆解任務 → 派發 omp worker → 等待 → 驗收 → 合併 |
| `orca-omp-doctor` | `/orca-omp-doctor` | 檢查整套設定是否可用 |
| `orca-omp-setup` | `/orca-omp-setup` | 查看與修改個人設定（模型、上限） |

## 流程

1. Opus 讀碼，把需求拆成小 Task（Target / Change / Constraints / Ownership / Acceptance）。
2. 依敏感度選 worker 模型：一般任務用 `ORCA_OMP_MODEL`，碰到金鑰、個人資料、未公開程式碼的任務用 `ORCA_OMP_LOCAL_MODEL`（必須在本機）。
3. `orca orchestration worker-start --agent omp --worktree new-child` 平行派發，每個 Task 一個子 worktree，在 Orca 視窗裡即時可見。
4. `orca orchestration check --wait` 等 `worker_done`；Opus 自己看 diff、跑測試，合格才合併並 `worker-release`，不合格就附上錯誤重派。

## 需求

- [Claude Code](https://claude.com/claude-code)
- Orca.app 與 `orca` CLI
- `omp`，並在 `~/.omp/agent/models.yml` 設定好 worker 模型的 provider（一般 + 本機各一）
- `python3`、`curl`、`git`

> omp 請使用 API key 或非 Claude 訂閱的 provider。用 Claude 訂閱的 OAuth 登入第三方工具可能違反 Anthropic 的使用條款。

## 安裝

```bash
git clone https://github.com/Jack-R-Hong/claude-orca-omp-skills.git
cd claude-orca-omp-skills
./install.sh            # 把 skills/* symlink 到 ~/.claude/skills/
```

接著在 Claude Code 裡執行 `/orca-omp-setup`。它會列出你的 omp 模型（標示本機或遠端），詢問要用哪個，並儲存你的選擇。

### 設定

設定屬於個人，存在 repo 以外的 `~/.config/orca-omp/config.env`（可用 `ORCA_OMP_CONFIG` 改路徑）。用 `/orca-omp-setup` 修改，或直接：

```bash
C=~/.claude/skills/orca-omp-setup/scripts/config.sh
bash $C show                                          # 目前的值與來源
bash $C models                                        # omp 模型，標示 local / remote
bash $C set ORCA_OMP_MODEL <provider/model>           # 寫入前會先驗證
```

| 設定 | 預設 | 用途 |
|---|---|---|
| `ORCA_OMP_MODEL` | 無 | 一般任務用的 omp 模型 |
| `ORCA_OMP_LOCAL_MODEL` | 無 | 機密任務用的 omp 模型，必須在 localhost |
| `ORCA_OMP_KEEP_WORKERS` | `1` | 任務完成後保留 Orca 裡的 worker 終端機（`0` 為關閉） |
| `ORCA_OMP_WAIT_MINUTES` | `15` | 每次等待 worker 的分鐘數，1–50 |
| `ORCA_OMP_MAX_LOCAL_WORKERS` | `2` | 同時執行的本機模型 worker 上限 |

同名的環境變數會覆蓋設定檔。設定檔只會被當成 `KEY=VALUE` 文字解析，不會被執行。

## 從 Orca 裡啟動 Claude Code 當編排者

Claude Code 必須在 **Orca 的終端機裡**執行，Opus 的編排過程才會和所有 worker 顯示在同一個 Orca 視窗。Orca 會在自己的終端機裡設定 `ORCA_TERMINAL_HANDLE`，skill 靠它辨識 coordinator。

### 1. 把專案加進 Orca

```bash
orca open                                   # 啟動 Orca（已開啟可略過）
orca repo add --path ~/Developer/<repo>     # 註冊專案（只需一次）
```

### 2. 啟動 Claude Code

擇一：

**A. 用 CLI 啟動（建議）**

```bash
orca agent launch --agent claude --worktree path:$HOME/Developer/<repo> \
  --surface terminal --model opus --focus
```

`--surface terminal` 讓 Claude Code 以終端機形式執行（不是 Orca 的 chat 介面），確保有 `ORCA_TERMINAL_HANDLE`。

**B. 在 Orca 介面裡**

在側邊欄選擇專案，開一個新的終端機分頁，輸入 `claude`。

**C. 接續既有的 Claude Code 對話**

在 Orca 的終端機分頁裡切到原本啟動那段對話的目錄，執行：

```bash
claude --resume <session-id>
```

接續後，請關掉原本在 Orca 外面的那個 Claude Code，避免兩邊同時操作同一段對話。

### 3. 確認並開始

在 Orca 裡的 Claude Code 中：

1. `/orca-omp-doctor`：`running inside an Orca terminal` 應該是 PASS。
2. `/orca-omp <任務描述>`

### 在 Orca 裡會看到什麼

- **主專案底下**：Claude Code（Opus）的編排對話。
- **每個子 worktree 底下**（側邊欄）：一個 omp worker 的終端機，即時顯示它在做什麼。
- `ORCA_OMP_KEEP_WORKERS=1`（預設）時，任務完成後 worker 終端機會保留，可以在那裡輸入 `/dump` 查看 omp 送給模型的完整 context。

## 使用

1. 檢查設定：`/orca-omp-doctor`（實測模型加上「用 --live」）。
2. 依上一節在 Orca 的終端機裡啟動 Claude Code。
3. `/orca-omp <任務描述>`

不在 Orca 終端機裡也能跑：skill 會自己建立一個 coordinator 終端機當身份，但 Opus 的對話不會顯示在 Orca 中。

## 注意事項

- 本機路線只保證資料不外流，不代表動作比較安全：worker 一樣能在本機執行指令。機密任務的 spec 會明列允許的檔案與指令。
- 小型或高度量化的模型可能忘記送 `worker_done`，skill 會在連續三次空等後改用 `worker-list` / `terminal read` 檢查。
- 每次等待維持 15 分鐘以內，讓 Claude Code 的 prompt cache 不會失效。

## Install guide for AI agents

> 這一節是寫給 AI agent（例如 Claude Code）讀的安裝步驟，刻意保留英文。你可以直接對 agent 說：「照 README 的 Install guide for AI agents 幫我安裝」。

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
4. How to use it: start Claude Code inside an Orca terminal (see the section "從 Orca 裡啟動 Claude Code 當編排者" in this README), then `/orca-omp <task>`. If the new skills do not appear in the current Claude Code session, start a new session.

### Uninstall
```bash
for s in orca-omp orca-omp-doctor orca-omp-setup; do [ -L "$HOME/.claude/skills/$s" ] && rm "$HOME/.claude/skills/$s"; done
rm -r "$HOME/.config/orca-omp"    # personal settings; ask the user first
```

## License

MIT
