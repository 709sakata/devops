#!/bin/bash
# shellcheck shell=bash
set -euo pipefail
# ============================================================
# 🔍 type-safety.sh
# any型検出 → Issue起票
# 実行頻度: 月・水・金
# ============================================================

# [C-1] SCRIPT_DIR をスクリプト自身のパスから動的に解決
SCRIPT_DIR="$(cd "$(dirname "$(realpath "$0")")" && pwd)"
# shellcheck source=./common.sh
source "${SCRIPT_DIR}/common.sh"

# [P0-2] 必須コマンドの事前検証
require_command gh || exit 1

LABELS=$(resolve_labels "any_type")

for i in "${!REPOS[@]}"; do
  REPO="${REPOS[$i]}"
  DIR="${REPO_DIRS[$i]}"

  log "🔍 [$REPO] any型検出中..."
  # [H-7] cd エラーを明示的にチェック（存在しないディレクトリでの誤実行を防止）
  if ! cd "$DIR" 2>/dev/null; then
    log "  ❌ リポジトリディレクトリが見つかりません: $DIR"
    continue
  fi

  EXISTING=$(get_existing_titles "$REPO")

  # 検出結果を一時ファイルに保存
  # [H-2] .tsx ファイルも対象に追加（React コンポーネントの any 型を検出）
  # [P2-1] MAX_ANY_TYPE_FILES を config.sh の定数で統一
  DETECTIONS=$(grep -rn ": any[,;\) ]" src/ --include="*.ts" --include="*.tsx" \
    | grep -v "node_modules" \
    | grep -v "\.d\.ts" \
    | grep -v "// eslint-disable" \
    | grep -v "__tests__" \
    | grep -v "\.test\.ts" \
    | grep -v "\.spec\.ts" \
    | grep -v "__generated__" \
    | grep -v "generated" \
    | grep -v "graphql\.ts" \
    | awk -F: '!seen[$1]++' \
    | head -"$MAX_ANY_TYPE_FILES")

  if [ -z "$DETECTIONS" ]; then
    log "  ℹ️  検出なし"
    continue
  fi

  echo "$DETECTIONS" | while IFS=: read -r file line code; do
    short_file="${file#src/}"

    if issue_exists "$EXISTING" "$short_file"; then
      log "  ⏭️  スキップ（既存Issue）: $short_file"
      continue
    fi

    log "  🤖 Issue生成中: $file:$line"
    BODY_CONTENT=$(generate_issue_body "$file" "$line" "$code" "any_type")

    # 生成失敗時はスキップ
    if [ "$BODY_CONTENT" = "※ AI分析生成失敗。手動で確認してください。" ]; then
      log "  ⚠️  生成失敗のためスキップ: $file:$line"
      continue
    fi

    TITLE="[Refactor] any型の乱用: $short_file"
    BODY="## 場所\n\`$file:$line\`\n\n## 問題のコード\n\`\`\`typescript\n$code\`\`\`\n\n$BODY_CONTENT\n\n---\n_自動検出: type-safety agent ($DATE)_"

    # [P4] create_issue 共通関数で起票
    # shellcheck disable=SC2086
    create_issue "$REPO" "$TITLE" "$BODY" $LABELS
  done

  log "✅ [$REPO] any型検出 完了"
done
