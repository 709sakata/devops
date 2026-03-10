#!/bin/bash
# ============================================================
# 共通ユーティリティ（全エージェントからsourceして使う）
# ============================================================

REPOS=(
  "Hopin-inc/civicship-api"
  "Hopin-inc/civicship-portal"
)
REPO_DIRS=(
  "$HOME/ghq/github.com/Hopin-inc/civicship-api"
  "$HOME/ghq/github.com/Hopin-inc/civicship-portal"
)
OLLAMA_MODEL="qwen2.5-coder:7b"
OLLAMA_URL="http://127.0.0.1:11435/api/generate"
DATE=$(date +"%Y-%m-%d")
LOG_DIR="$HOME/scripts/audit/logs"
LOG_FILE="$LOG_DIR/$DATE.log"

log() {
  echo "[$(date +'%H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# ============================================================
# Ollamaに短いプロンプトを投げてIssue文章を生成
# 生成失敗時は空文字を返す
# ============================================================
generate_issue_body() {
  local file="$1"
  local line="$2"
  local code="$3"
  local type="$4"

  local prompt=""
  case "$type" in
    any_type)
      prompt="TypeScriptのコードレビューをしてください。
ファイル: $file / 行番号: $line / コード: $code
any型の問題点と改善案を以下の形式で答えてください：
問題: （1文）
改善案: （1文）"
      ;;
    eslint)
      prompt="ESLintエラーの改善案を教えてください。
ファイル: $file / 行番号: $line / エラー: $code
以下の形式で答えてください：
問題: （1文）
改善案: （1文）"
      ;;
    security)
      prompt="セキュリティ脆弱性の対応方針を教えてください。
パッケージ: $file / 修正バージョン: $line / 脆弱性: $code
以下の形式で答えてください：
問題: （リスクの概要1文）
対応: （pnpm updateコマンドを含む1文）"
      ;;
  esac

  local response
  response=$(curl -s --max-time 30 "$OLLAMA_URL" \
    -H "Content-Type: application/json" \
    -d "{
      \"model\": \"$OLLAMA_MODEL\",
      \"prompt\": $(echo "$prompt" | jq -Rs .),
      \"stream\": false,
      \"options\": { \"temperature\": 0.1, \"num_ctx\": 1024, \"num_predict\": 200 }
    }" | jq -r '.response // ""')

  # 生成失敗・空の場合はフォールバックテキストを返す
  if [ -z "$response" ] || [ "$response" = "生成失敗" ]; then
    echo "※ AI分析生成失敗。手動で確認してください。"
  else
    echo "$response"
  fi
}

# ============================================================
# 既存Issue確認（open + closed両方・500件）
# Wontfixラベルのものも除外対象に含む
# ============================================================
get_existing_titles() {
  local repo="$1"
  gh issue list \
    --repo "$repo" \
    --state open \
    --limit 500 \
    --json title \
    --jq '.[].title' 2>/dev/null | cat || echo ""
}

# Issueが既に存在するか確認
issue_exists() {
  local existing_titles="$1"
  local keyword="$2"
  echo "$existing_titles" | grep -qF "$keyword"
}

# ============================================================
# ラベル判断（ルールベース）
# ============================================================
resolve_labels() {
  local type="$1"

  case "$type" in
    any_type|eslint)
      echo "refactor,Priority: Low"
      ;;
    security_high)
      echo "Problem: Security,Priority: High"
      ;;
    security_medium)
      echo "Problem: Security,Priority: Low"
      ;;
    deps)
      echo "Type: Dependencies,Priority: Low"
      ;;
    *)
      echo "Type: Task"
      ;;
  esac
}

# ============================================================
# pnpmのパス確認
# ============================================================
check_pnpm() {
  if ! command -v pnpm &> /dev/null; then
    # Node.js環境のパスを追加して再確認
    export PATH="$HOME/.npm-global/bin:/usr/local/bin:$PATH"
    if ! command -v pnpm &> /dev/null; then
      log "❌ pnpmが見つかりません"
      return 1
    fi
  fi
  return 0
}

# ----------------------------------------------------------
# Ollama汎用呼び出し
# ----------------------------------------------------------
call_ollama() {
  local prompt="$1"
  curl -s --max-time 60 "$OLLAMA_URL" \
    -H "Content-Type: application/json" \
    -d "{
      \"model\": \"$OLLAMA_MODEL\",
      \"prompt\": $(echo "$prompt" | jq -Rs .),
      \"stream\": false,
      \"options\": { \"temperature\": 0.1, \"num_ctx\": 2048, \"num_predict\": 400 }
    }" | jq -r '.response // ""'
}
