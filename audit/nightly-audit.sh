#!/bin/bash
SCRIPT_DIR="$HOME/scripts/audit"
LOG_DIR="$SCRIPT_DIR/logs"
DATE=$(date +"%Y-%m-%d")
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/$DATE.log"

log() {
  echo "[$(date +'%H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log "🚀 nightly-audit 開始 ($DATE)"

OLLAMA_OK=false
for i in 1 2 3; do
  if curl -s "http://127.0.0.1:11435" > /dev/null 2>&1; then
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

log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log "🔒 security エージェント起動"
bash "$SCRIPT_DIR/agents/security.sh"

DAY_OF_WEEK=$(date +%u)
if [[ "$DAY_OF_WEEK" == "1" || "$DAY_OF_WEEK" == "3" || "$DAY_OF_WEEK" == "5" ]]; then
  log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  log "🔍 type-safety エージェント起動"
  bash "$SCRIPT_DIR/agents/type-safety.sh"

  log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  log "🔍 eslint エージェント起動"
  bash "$SCRIPT_DIR/agents/eslint.sh"
else
  log "ℹ️  本日はリファクタ監査スキップ（月・水・金のみ実行）"
fi

log "🎉 全監査完了 | ログ: $LOG_FILE"
