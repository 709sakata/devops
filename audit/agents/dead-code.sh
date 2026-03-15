#!/bin/bash
# shellcheck shell=bash
set -euo pipefail
# ============================================================
# 🧹 dead-code.sh
# 未使用のTypeScriptエクスポートを検出 → Issue起票
# 実行頻度: 火曜日
# ============================================================

# [C-1] SCRIPT_DIR をスクリプト自身のパスから動的に解決
SCRIPT_DIR="$(cd "$(dirname "$(realpath "$0")")" && pwd)"
# shellcheck source=./common.sh
source "${SCRIPT_DIR}/common.sh"

# [P0-2] 必須コマンドの事前検証
require_command gh || exit 1

MAX_ISSUES=15

for i in "${!REPOS[@]}"; do
  REPO="${REPOS[$i]}"
  DIR="${REPO_DIRS[$i]}"

  log "🧹 [$REPO] 未使用エクスポート検出中..."

  if [[ ! -d "$DIR/src" ]]; then
    log "  ❌ src/ ディレクトリが見つかりません: $DIR"
    continue
  fi

  EXISTING=$(get_existing_titles "$REPO")

  # exportされたシンボルを収集（テスト・生成ファイル除外）
  EXPORTED=$(grep -rn --include="*.ts" --include="*.tsx" \
    -E "^export (const|function|class|type|interface|enum) [A-Za-z_][A-Za-z0-9_]*" \
    "$DIR/src/" \
    | grep -v "__tests__" \
    | grep -v "\.test\.ts" \
    | grep -v "\.spec\.ts" \
    | grep -v "__generated__" \
    | grep -v "generated\.ts" \
    | grep -v "graphql\.ts" \
    | grep -v "index\.ts" \
    2>/dev/null || true)

  if [[ -z "$EXPORTED" ]]; then
    log "  ℹ️  [$REPO] エクスポート定義なし、スキップ"
    continue
  fi

  # 未使用候補を検出（自ファイル以外からのインポートなし）
  DEAD_CANDIDATES=""
  COUNT=0

  while IFS=: read -r filepath lineno declaration; do
    [[ $COUNT -ge $MAX_ISSUES ]] && break

    # シンボル名を抽出
    SYMBOL=$(echo "$declaration" | sed -E 's/^export (const|function|class|type|interface|enum) ([A-Za-z_][A-Za-z0-9_]*).*/\2/')
    REL_PATH="${filepath#"$DIR/"}"

    # 他ファイルからのインポート数を検索（自ファイル除外）
    IMPORT_COUNT=$(grep -rl --include="*.ts" --include="*.tsx" \
      -F "$SYMBOL" \
      "$DIR/src/" \
      2>/dev/null \
      | grep -v "$filepath" \
      | grep -v "__tests__" \
      | grep -v "__generated__" \
      | wc -l || echo "0")

    if [[ "$IMPORT_COUNT" -eq 0 ]]; then
      DEAD_CANDIDATES+="| \`${REL_PATH}:${lineno}\` | \`${SYMBOL}\` |\n"
      COUNT=$((COUNT + 1))
    fi
  done <<< "$EXPORTED"

  if [[ -z "$DEAD_CANDIDATES" ]]; then
    log "  ✅ [$REPO] 未使用エクスポート検出なし"
    continue
  fi

  # Ollamaで分析コメント生成
  PROMPT="以下のTypeScript未使用エクスポート候補を確認してください。
各シンボルが本当に不要か、または index.ts 経由で re-export されている可能性も考慮し、
削除・整理の優先度を日本語で簡潔に提案してください。

$(echo -e "$DEAD_CANDIDATES" | sed 's/| `//g; s/` |//g; s/|//g' | head -15)

前置き・後書き不要。「シンボル名: 提案」の形式で答えてください。"

  SUGGESTION="$(call_ollama "$PROMPT")"

  TITLE="[suggest] 未使用エクスポート候補 ($(basename "$REPO"))"

  if issue_exists "$EXISTING" "$TITLE"; then
    log "  ⏭️  [$REPO] 既存Issueあり、スキップ"
    continue
  fi

  BODY="## 🧹 未使用エクスポート候補\n\n"
  BODY+="他ファイルからインポートされていない \`export\` 定義です。\n"
  BODY+="※ \`index.ts\` での re-export や動的インポートは検出できないため、削除前に手動確認してください。\n\n"
  BODY+="| ファイル | シンボル |\n"
  BODY+="|---|---|\n"
  BODY+="${DEAD_CANDIDATES}"
  BODY+="\n### 💡 整理提案\n\n${SUGGESTION}\n"
  BODY+="\n---\n_自動検出: dead-code agent ($DATE)_"

  # [P4] create_issue 共通関数で起票
  create_issue "$REPO" "$TITLE" "$BODY" "refactor" "Priority: Low"

  log "✅ [$REPO] 未使用エクスポート検出 完了"
done
