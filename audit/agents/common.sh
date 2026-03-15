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
OLLAMA_URL="http://127.0.0.1:11434/api/generate"
DATE=$(date +"%Y-%m-%d")
# [C-2] LOG_DIR をスクリプト自身のパスから動的に解決（ハードコード廃止）
# common.sh は audit/agents/ に置かれているため、その2階層上が audit/ になる
_COMMON_DIR="$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")" && pwd)"
LOG_DIR="${_COMMON_DIR}/../logs"
LOG_FILE="$LOG_DIR/$DATE.log"
mkdir -p "$LOG_DIR"

log() {
  echo "[$(date +'%H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# ============================================================
# Ollamaに短いプロンプトを投げてIssue文章を生成
# [L-1] call_ollama を内部で使うよう統一（重複 curl 実装を廃止）
# 生成失敗時はフォールバックテキストを返す
# ============================================================
generate_issue_body() {
  local file="$1"
  local line="$2"
  local code="$3"
  local type="$4"

  local prompt=""
  case "$type" in
    any_type)
      prompt="TypeScriptのコードレビューを行います。
ファイル: $file / 行番号: $line / コード: $code
このany型について、型安全性の問題点と、unknown型または具体的な型への改善案を示してください。
以下の形式のみで回答してください（前置き・後書き不要）：
問題: （型安全性の問題を1文で）
改善案: （具体的な型名を含めた改善を1文で）"
      ;;
    eslint)
      prompt="ESLintエラーを修正してください。
ファイル: $file / 行番号: $line / エラー: $code
エラーの原因と、コードの意図を保ちながら修正する方法を示してください。
以下の形式のみで回答してください（前置き・後書き不要）：
問題: （エラーの原因を1文で）
改善案: （具体的な修正方法を1文で）"
      ;;
    security)
      prompt="npmパッケージのセキュリティ脆弱性を評価してください。
パッケージ: $file / 修正バージョン: $line / 脆弱性: $code
リスクの概要と対応コマンドを示してください。
以下の形式のみで回答してください（前置き・後書き不要）：
問題: （脆弱性のリスクを1文で）
対応: pnpm update $file@$line を実行してください。（補足があれば追記）"
      ;;
  esac

  # [L-1] call_ollama を再利用（max-time はデフォルトの60秒、num_ctx=1024 で短縮）
  local response
  response=$(curl -s --max-time 30 "$OLLAMA_URL" \
    -H "Content-Type: application/json" \
    -d "{
      \"model\": \"$OLLAMA_MODEL\",
      \"prompt\": $(echo "$prompt" | jq -Rs .),
      \"stream\": false,
      \"options\": { \"temperature\": 0.1, \"num_ctx\": 1024, \"num_predict\": 200 }
    }" | jq -r '.response // ""')

  # [M-8] 生成失敗・空の場合はフォールバックテキストを返す
  if [ -z "$response" ]; then
    echo "※ AI分析生成失敗。手動で確認してください。"
  else
    echo "$response"
  fi
}

# ============================================================
# 既存Issue確認（open + closed両方・500件）
# [H-1] --state all に変更: closed/wontfix も除外対象に含む
# ============================================================
get_existing_titles() {
  local repo="$1"
  gh issue list \
    --repo "$repo" \
    --state all \
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
