#!/bin/bash
# shellcheck shell=bash
# ============================================================
# 共通ユーティリティ（全エージェントからsourceして使う）
# ============================================================

# [C-2] LOG_DIR をスクリプト自身のパスから動的に解決（ハードコード廃止）
_COMMON_DIR="$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")" && pwd)"
LOG_DIR="${_COMMON_DIR}/../logs"
LOG_FILE="$LOG_DIR/$(date +"%Y-%m-%d").log"
mkdir -p "$LOG_DIR"

# ----------------------------------------------------------
# [P2-1] 定数を config.sh から読み込む（変更は config.sh のみ）
# ----------------------------------------------------------
# shellcheck source=./config.sh
source "${_COMMON_DIR}/config.sh"

# ----------------------------------------------------------
# [P0-1] PATH 正規化 — cron 環境では /usr/local/bin 等が欠落する
# 本関数は common.sh の source 直後に自動実行される
# ----------------------------------------------------------
setup_path() {
  local additions=(
    "/usr/local/bin"
    "/opt/homebrew/bin"
    "$HOME/.npm-global/bin"
    "/usr/local/sbin"
  )
  local p
  for p in "${additions[@]}"; do
    # [P0-1] if文で記述: [[ ]] && は set -e 環境でfalsy時に終了コード1を返すため使用しない
    if [[ ":$PATH:" != *":$p:"* ]]; then
      export PATH="$p:$PATH"
    fi
  done
}
setup_path

# ----------------------------------------------------------
# ターゲットリポジトリ
# ----------------------------------------------------------
REPOS=(
  "Hopin-inc/civicship-api"
  "Hopin-inc/civicship-portal"
)
REPO_DIRS=(
  "$HOME/ghq/github.com/Hopin-inc/civicship-api"
  "$HOME/ghq/github.com/Hopin-inc/civicship-portal"
)
DATE=$(date +"%Y-%m-%d")

# ----------------------------------------------------------
# ログ関数
# ----------------------------------------------------------
log() {
  echo "[$(date +'%H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# [P1-1] 構造化ログ（JSONL形式）— run_id による相関追跡が可能
# 使い方: log_json "INFO" "メッセージ" "key1" "val1" "key2" "val2"
log_json() {
  local level="$1" msg="$2"
  shift 2
  local json
  json="$(jq -n \
    --arg ts  "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
    --arg lvl "$level" \
    --arg msg "$msg" \
    --arg run "${RUN_ID:-}" \
    '{ts: $ts, level: $lvl, msg: $msg, run_id: $run}')"
  # 追加フィールドを key=value ペアで受け取る
  while [[ $# -ge 2 ]]; do
    json="$(printf '%s' "$json" | jq --arg k "$1" --arg v "$2" '. + {($k): $v}')"
    shift 2
  done
  printf '%s\n' "$json" >> "${LOG_FILE%.log}.jsonl"
  log "$level $msg"
}

# ----------------------------------------------------------
# [P0-2] 依存コマンド事前検証
# 使い方: require_command gh || exit 1
# ----------------------------------------------------------
require_command() {
  local cmd="$1"
  if ! command -v "$cmd" > /dev/null 2>&1; then
    log "❌ 必須コマンドが見つかりません: $cmd (PATH=$PATH)"
    return 1
  fi
}

# ----------------------------------------------------------
# [P4] Issue作成の共通関数（DRY）
# 使い方: create_issue "$REPO" "$TITLE" "$BODY" "label1" "label2"
# ----------------------------------------------------------
create_issue() {
  local repo="$1" title="$2" body="$3"
  shift 3
  local label_args=()
  for label in "$@"; do label_args+=(--label "$label"); done

  local result
  if result="$(gh issue create \
      --repo "$repo" \
      --title "$title" \
      --body "$(printf '%b' "$body")" \
      "${label_args[@]}" 2>&1)"; then
    log_json "INFO" "issue created" "repo" "$repo" "title" "$title"
    return 0
  else
    log_json "WARN" "issue creation failed" \
      "repo" "$repo" "title" "$title" "error" "$result"
    printf '%s\n' "$result" >> "$LOG_FILE"
    return 1
  fi
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

  # [P3-1] jq -n でJSON構築（bash文字列補間によるインジェクション防止）
  local body result
  body="$(jq -n \
    --arg model  "$OLLAMA_MODEL" \
    --arg prompt "$prompt" \
    --argjson ctx  1024 \
    --argjson pred 200 \
    '{model: $model, prompt: $prompt, stream: false,
      options: {temperature: 0.1, num_ctx: $ctx, num_predict: $pred}}')"
  result="$(curl -s --max-time "$OLLAMA_TIMEOUT_SHORT" "$OLLAMA_URL" \
    -H "Content-Type: application/json" \
    -d "$body" | jq -r '.response // ""')"

  # [M-8] 生成失敗・空の場合はフォールバックテキストを返す
  if [[ -z "$result" ]]; then
    echo "※ AI分析生成失敗。手動で確認してください。"
  else
    echo "$result"
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
# [P3-1] Ollama汎用呼び出し — jq -n で安全にJSON構築
# ----------------------------------------------------------
call_ollama() {
  local prompt="$1"
  local timeout="${2:-$OLLAMA_TIMEOUT_LONG}"
  local body
  body="$(jq -n \
    --arg model  "$OLLAMA_MODEL" \
    --arg prompt "$prompt" \
    '{model: $model, prompt: $prompt, stream: false,
      options: {temperature: 0.1, num_ctx: 2048, num_predict: 400}}')"
  curl -s --max-time "$timeout" "$OLLAMA_URL" \
    -H "Content-Type: application/json" \
    -d "$body" \
    | jq -r '.response // ""'
}
