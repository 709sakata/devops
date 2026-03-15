#!/bin/bash
set -euo pipefail
# ============================================================
# 🔍 type-safety.sh
# any型検出 → Issue起票
# 実行頻度: 月・水・金
# ============================================================

source "$(dirname "$0")/common.sh"

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
    | head -20)

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

    # [L-2] echo -e の代わりに printf で確実に改行展開
    gh issue create \
      --repo "$REPO" \
      --title "$TITLE" \
      --body "$(printf '%b' "$BODY")" \
      --label "$LABELS" \
      2>>"$LOG_FILE" \
      && log "  ✅ 起票: $TITLE" \
      || log "  ⚠️  起票失敗: $TITLE (詳細: $LOG_FILE)"
  done

  log "✅ [$REPO] any型検出 完了"
done
