# claude-orca-omp-skills

[English](README.md) | **繁體中文**

Claude Code skills：讓 Claude Code（Opus）當 [Orca](https://github.com/stablyai/orca) orchestration 的 coordinator，把 coding 子任務派給 [oh-my-pi](https://github.com/can1357/oh-my-pi)（`omp`）worker 執行，最後由 Opus 驗收。機密任務會改派給跑在本機的模型，資料不離開這台機器。

| Skill | 指令 | 用途 |
|---|---|---|
| `orca-omp` | `/orca-omp <任務>` | 拆解任務 → 派發 omp worker → 等待 → 驗收 → 合併 |
| `orca-omp-doctor` | `/orca-omp-doctor` | 檢查整套設定是否可用 |

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

設定 worker 模型（omp 的 `provider/model` selector，可用 `omp models` 查）：

```bash
export ORCA_OMP_MODEL="strata/qwen3.8-flash-next-coder-iq1_m"   # 一般任務
export ORCA_OMP_LOCAL_MODEL="omlx/Qwen3.8-27B-MLX-4bit"         # 機密任務，必須在本機
```

未設定時使用上面的預設值（作者自己的環境），請改成你的模型。

## 使用

1. 檢查設定：`/orca-omp-doctor`（實測模型加上「用 --live」）。
2. 在 **Orca 的終端機裡**啟動 Claude Code，編排過程和所有 worker 才會顯示在同一個視窗。
3. `/orca-omp <任務描述>`

不在 Orca 終端機裡也能跑：skill 會自己建立一個 coordinator 終端機當身份，但 Opus 的對話不會顯示在 Orca 中。

## 注意事項

- 本機路線只保證資料不外流，不代表動作比較安全：worker 一樣能在本機執行指令。機密任務的 spec 會明列允許的檔案與指令。
- 小型或高度量化的模型可能忘記送 `worker_done`，skill 會在連續三次空等後改用 `worker-list` / `terminal read` 檢查。
- 每次等待維持 15 分鐘以內，讓 Claude Code 的 prompt cache 不會失效。

## License

MIT
