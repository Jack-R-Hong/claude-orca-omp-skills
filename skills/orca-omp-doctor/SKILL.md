---
name: orca-omp-doctor
description: 檢查 orca-omp 編排流程的設定：Claude Code、Orca runtime、omp agent、worker 模型、本機模型是否真的在本機、skill 安裝。使用者說 /orca-omp-doctor、「檢查 omp 設定」、「orca-omp 壞了」，或 /orca-omp 前置步驟失敗時使用。
---

# orca-omp 設定檢查

1. 執行檢查腳本（不會印出任何金鑰）：
   ```bash
   bash ~/.claude/skills/orca-omp-doctor/scripts/doctor.sh
   ```
   使用者要求實測模型，或基本檢查全過但 worker 仍失敗時，加 `--live`：會對每個 worker 模型送一句 `Reply with exactly: OK`，每個最多 2 分鐘。
2. 依結果回報：先列 FAIL，再列 WARN，每項附腳本給的 `→` 修正建議。全部 PASS 就一句話說明可以用 `/orca-omp`。
3. 修正需要改設定或啟動服務時（例如 `orca open`、編輯 `~/.omp/agent/models.yml`），先說明要做什麼並徵求同意；`omp login` 等互動指令請使用者自己用 `! <指令>` 執行。
4. 修正後重跑腳本確認。

## 檢查項目
| 區塊 | 內容 |
|---|---|
| Commands | `claude`、`orca`、`omp`、`git`、`python3`、`curl` 在 PATH 中 |
| Orca | runtime 為 ready；接受 agent id `omp`；可取得 orchestration 指南；是否在 Orca 終端機內（否則 coordinator 不會顯示在 Orca） |
| omp models | `ORCA_OMP_MODEL` 與 `ORCA_OMP_LOCAL_MODEL` 都在 `omp models` 中 |
| Local model stays local | 本機模型的 provider `baseUrl` 指向 localhost，且伺服器有回應 |
| Skills installed | 兩個 skill 都在 `~/.claude/skills/` |
