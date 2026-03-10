#!/bin/bash
# code-quality.sh - コード品質サジェストのオーケストレーター
# 実行タイミング: 週1回・月曜
# crontab例: 0 3 * * 1 ~/scripts/suggest/code-quality.sh >> ~/scripts/suggest/logs/code-quality.log 2>&1

set -euo pipefail

AGENTS_DIR="${HOME}/scripts/suggest/agents"
source "${HOME}/scripts/audit/agents/common.sh"

log "=== code-quality suggest 開始 $(date '+%Y-%m-%d %H:%M:%S') ==="

for i in "${!REPOS[@]}"; do
  repo="${REPOS[$i]}"
  repo_dir="${REPO_DIRS[$i]}"
  repo_name="$(basename "$repo")"

  if [[ ! -d "$repo_dir" ]]; then
    log "[$repo_name] リポジトリが見つかりません: $repo_dir"
    continue
  fi

  log "[$repo_name] ---- 開始 ----"
  # [L-3] set -euo pipefail 環境下でも後続エージェントが必ず実行されるよう || でエラーをキャッチ
  bash "${AGENTS_DIR}/uncommented.sh" "$repo" "$repo_dir" || log "[$repo_name] ⚠️  uncommented 異常終了"
  bash "${AGENTS_DIR}/naming.sh"      "$repo" "$repo_dir" || log "[$repo_name] ⚠️  naming 異常終了"
  bash "${AGENTS_DIR}/complexity.sh"  "$repo" "$repo_dir" || log "[$repo_name] ⚠️  complexity 異常終了"
  log "[$repo_name] ---- 完了 ----"
done

log "=== code-quality suggest 完了 ==="
