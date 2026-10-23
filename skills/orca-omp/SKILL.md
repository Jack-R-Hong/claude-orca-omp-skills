---
name: orca-omp
description: 編排模式：Claude Code（Opus）當 Orca orchestration 的 coordinator 負責拆解任務與驗收，把 coding 子任務派給 oh-my-pi (omp) worker 執行，機密任務改派本機模型。使用者說 /orca-omp、「用 omp 做」、「派給 omp」時使用。設定有問題時先跑 /orca-omp-doctor。
---

# Opus 編排 + Orca + omp 執行

你（Opus）是 Orca orchestration 的 coordinator：讀碼、拆任務、派發、驗收。實作交給 omp worker，除非同一任務的 worker 失敗兩次，否則不要自己寫實作。

## 設定
worker 模型由環境變數決定，未設定時用預設值（omp 的 `provider/model` selector，可用 `omp models` 查）：

| 變數 | 預設 | 用途 |
|---|---|---|
| `ORCA_OMP_MODEL` | `strata/qwen3.8-flash-next-coder-iq1_m` | 一般任務 |
| `ORCA_OMP_LOCAL_MODEL` | `omlx/Qwen3.8-27B-MLX-4bit` | 機密任務，必須是跑在本機的模型 |

開始前執行 `echo "${ORCA_OMP_MODEL:-strata/qwen3.8-flash-next-coder-iq1_m} ${ORCA_OMP_LOCAL_MODEL:-omlx/Qwen3.8-27B-MLX-4bit}"` 取得實際值。下文的 `<MODEL>` / `<LOCAL_MODEL>` 指這兩個值。

## 0. 前置
任一步失敗或第一次使用，先跑 `/orca-omp-doctor`。
1. 先載入版本相符的 Orca 規則並全程遵守（它是生命週期、ack、release 的權威來源）：
   `orca skills get orchestration`
2. `orca status --json`：runtime 未啟動就 `orca open`。
3. `orca repo list`：目標 repo 未註冊就 `orca repo add <path>`。
4. 最好在 Orca 內的終端機裡執行 Claude Code，使用者才能在同一個視窗看到所有 worker。
5. 若 `echo $ORCA_TERMINAL_HANDLE` 為空（Claude Code 不在 Orca 終端機裡），orchestration 指令會報 `no_active_sender_terminal`。此時先建立自己專屬的 coordinator 終端機，之後都用它的 handle：
   `orca terminal create --worktree path:<repo> --title "coordinator (Claude Code)" --json` → 取 `terminal.handle` 為 `<H>`。
   - `run-create`、`worker-start` 加 `--from <H>`；`worker-start` 另加 `--run <run_id>`。
   - `check` 加 `--run <run_id> --terminal <H>`（不是 `--from`）。
   - `worker-release` 只接受 `--dispatch <dispatch_id>`，不要加 `--run` / `--from`。
   - 絕不要用別的 pane（例如 worker）的 handle。

## 1. 拆解
- 先讀相關程式碼，拆成範圍小、彼此獨立的 Task（每個最好只動 1–3 個檔案）。
- 假設 worker 模型能力有限（小型或高度量化的本地模型）。每個 spec 都要符合 Orca 的 Task-spec contract：
  **Target**（檔案/函式）、**Change**（具體結果）、**Constraints**（不可動的部分）、**Ownership**（只能改哪些檔案）、**Observable acceptance**（驗收指令）。
- spec 結尾明確提醒 worker：完成後必須依 preamble 送出一次 `worker_done`，並標明 `--outcome succeeded|failed`。

## 2. 選擇 worker 模型
每個 Task 依敏感度選一條路線，並在回報中標明用了哪條：

| 路線 | `--model` | 何時用 |
|---|---|---|
| 一般（預設） | `<MODEL>` | 一般程式碼任務。 |
| 本機 | `<LOCAL_MODEL>` | 資料不能離開這台機器的任務：碰到 `.env`、金鑰、憑證、`~/.ssh`、個人資料、未公開的程式碼或客戶資料；或需要讀寫本機系統設定、keychain 相關腳本。 |

- 本機模型與 Orca、Claude Code 共用同一台機器的記憶體與 GPU，同時只派 1–2 個本機 worker。
- 不確定是否敏感時選本機路線。
- 本機路線只保護「資料不外流」，不代表動作比較安全：worker 一樣能在這台機器執行指令。敏感任務的 spec 要明列允許的指令與檔案，禁止刪除、`git push`、對外網路請求，且不要把機密內容寫進 `worker_done` 摘要或 log。
- 機密任務的驗收由你在本機看 diff，不要把機密內容貼回對話給使用者以外的地方。

## 3. 派發
```bash
orca orchestration run-create --objective "<整體目標>" --json
# 互不相依的 Task 一次全部啟動，各自開子 worktree
orca orchestration worker-start --spec "<spec>" --task-title "<短標題>" \
  --worktree new-child --agent omp \
  --model <MODEL 或 LOCAL_MODEL> --json
```
- 有先後相依：用 `task-create --deps` + `worker-start --task <id>`，相依鏈不超過 3 層。
- OMP 不支援 `--effort`，不要傳。
- `worker-start` 失敗時不要直接重跑，依 Orca 規則讀 `failedStage` 並載入 recovery reference。

## 4. 等待與驗收
```bash
orca orchestration check --wait --types "worker_done,escalation,question" --timeout-ms 900000 --json
```
- Prompt cache：假設 cache TTL 是 1 小時（用量進入 overage 時可能降為 5 分鐘）。每次 `check --wait` 的 timeout 保持在 15 分鐘（最多 50 分鐘），讓每次醒來都落在 TTL 內，便宜地續住 cache；不要用超過 1 小時的單次等待。
- 保持 coordinator context 精簡，這樣即使 cache 失效重建也便宜：worker 輸出只讀需要的片段（`tail`、`jq`），不要把整段 terminal 輸出或大 diff 讀進對話；開始長時間等待前，先把已完成 Task 的結論濃縮成幾行。
- 收到 `question` 就用 `reply` 回答。收到 `worker_done` 時：
  - 用 `orca file diff` 或在該 worktree 跑 `git diff`，自己跑驗收指令，不要只相信 worker 的摘要。
  - 合格：合併回主分支，`worker-release`。
  - 不合格：在同一個 terminal 重派一次，附上具體錯誤與修正方向；仍失敗才由你接手。
- 弱模型可能忘了送 `worker_done`：連續三次空等後，照 Orca 規則用 `worker-list` 檢查，可用 `orca terminal read` 看 worker 輸出。沒有確切證據前不要 stop / abandon。
- 結束前確認 `worker-list --run <run_id> --terminal-state reclaimable --json` 為空。

## 5. 回報
每個 Task 列出：結果、證據（測試輸出/diff 摘要）、worktree 路徑、未解決的問題。
使用者可以在 Orca 視窗看每個 worker 的終端機；要看 omp 完整 context，在該 worker 的終端機下 `/dump`，或用 `omp render <session-id> --plain`。
