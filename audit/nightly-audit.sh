#!/bin/bash
set -euo pipefail
# [C-1] SCRIPT_DIR をスクリプト自身のパスから動的に解決（ハードコード廃止）
SCRIPT_DIR="$(cd "$(dirname "$(realpath "$0")")" && pwd)"
LOG_DIR="$SCRIPT_DIR/logs"
DATE=$(date +"%Y-%m-%d")
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/$DATE.log"

log() {
  echo "[$(date +'%H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# 30日以上前のログを削除（ログローテーション）
find "$LOG_DIR" -name "*.log" -mtime +30 -delete 2>/dev/null || true

log "🚀 nightly-audit 開始 ($DATE)"

# [M-2] Ollama の疎通確認を /api/tags エンドポイントで HTTP ステータスまで検証
OLLAMA_OK=false
for i in 1 2 3; do
  if curl -sf "http://127.0.0.1:11434/api/tags" > /dev/null 2>&1; then
    OLLAMA_OK=true
    break
  fi
  log "⏳ Ollama接続待機中... ($i/3)"
  sleep 5
done

if [ "$OLLAMA_OK" = false ]; then
  log "❌ Mac MiniのOllamaに接続できません。"
  exit 1
fi
log "✅ Mac Mini Ollama接続確認OK"

# [M-1] エージェントの終了コードを追跡してサマリーログに記録
FAILED_AGENTS=()

log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log "🔒 security エージェント起動"
if ! bash "$SCRIPT_DIR/agents/security.sh"; then
  FAILED_AGENTS+=("security")
  log "⚠️  security エージェントが異常終了しました"
fi

DAY_OF_WEEK=$(date +%u)
if [[ "$DAY_OF_WEEK" == "1" || "$DAY_OF_WEEK" == "3" || "$DAY_OF_WEEK" == "5" ]]; then
  log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  log "🔍 type-safety エージェント起動"
  if ! bash "$SCRIPT_DIR/agents/type-safety.sh"; then
    FAILED_AGENTS+=("type-safety")
    log "⚠️  type-safety エージェントが異常終了しました"
  fi

  log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  log "🔍 eslint エージェント起動"
  if ! bash "$SCRIPT_DIR/agents/eslint.sh"; then
    FAILED_AGENTS+=("eslint")
    log "⚠️  eslint エージェントが異常終了しました"
  fi
else
  log "ℹ️  本日はリファクタ監査スキップ（月・水・金のみ実行）"
fi

if [[ "$DAY_OF_WEEK" == "2" ]]; then
  log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  log "🧹 dead-code エージェント起動"
  if ! bash "$SCRIPT_DIR/agents/dead-code.sh"; then
    FAILED_AGENTS+=("dead-code")
    log "⚠️  dead-code エージェントが異常終了しました"
  fi
fi

if [[ ${#FAILED_AGENTS[@]} -gt 0 ]]; then
  log "⚠️  異常終了したエージェント: ${FAILED_AGENTS[*]}"
else
  log "🎉 全監査完了 | ログ: $LOG_FILE"
fi
