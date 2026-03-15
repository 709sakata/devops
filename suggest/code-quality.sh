#!/bin/bash
# code-quality.sh - コード品質サジェストのオーケストレーター
# 実行タイミング: 週1回・月曜
# crontab例: 0 3 * * 1 ~/ghq/github.com/709sakata/devops/suggest/code-quality.sh

set -euo pipefail

# [C-1] SCRIPT_DIR をスクリプト自身のパスから動的に解決（ハードコード廃止）
SCRIPT_DIR="$(cd "$(dirname "$(realpath "$0")")" && pwd)"
AGENTS_DIR="${SCRIPT_DIR}/agents"
source "${SCRIPT_DIR}/../audit/agents/common.sh"

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
  bash "${AGENTS_DIR}/pr-creator.sh"  "$repo" "$repo_dir" || log "[$repo_name] ⚠️  pr-creator 異常終了"
  log "[$repo_name] ---- 完了 ----"
done

log "=== code-quality suggest 完了 ==="
