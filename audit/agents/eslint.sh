#!/bin/bash
# ============================================================
# 🔍 eslint.sh
# ESLintエラー検出 → Issue起票
# 実行頻度: 月・水・金
# ============================================================

source "$(dirname "$0")/common.sh"

LABELS=$(resolve_labels "eslint")

for i in "${!REPOS[@]}"; do
  REPO="${REPOS[$i]}"
  DIR="${REPO_DIRS[$i]}"

  log "🔍 [$REPO] ESLint検出中..."
  cd "$DIR"

  # pnpmのパス確認
  if ! check_pnpm; then
    log "  ❌ pnpmが見つからないためスキップ: $REPO"
    continue
  fi

  EXISTING=$(get_existing_titles "$REPO")

  # ESLint実行・エラー0件なら早期リターン
  ESLINT_OUTPUT=$(pnpm eslint src/ --format json 2>/dev/null)
  # [H-8] ESLint 実行失敗時に jq が空文字を返す場合を考慮して 0 にフォールバック
  ERROR_COUNT=$(echo "$ESLINT_OUTPUT" | jq '[.[] | .errorCount] | add // 0' 2>/dev/null)
  ERROR_COUNT="${ERROR_COUNT:-0}"

  if [ "${ERROR_COUNT}" -eq 0 ]; then
    log "  ✅ ESLintエラーなし"
    continue
  fi

  log "  📊 ESLintエラー検出: ${ERROR_COUNT}件"

  # [M-6] 区切り文字を SOH (\x01) に変更: ESLint メッセージに | が含まれても分割が崩れない
  SEP=$'\x01'
  DETECTIONS=$(echo "$ESLINT_OUTPUT" \
    | jq -r --arg sep $'\x01' '.[] | select(.errorCount > 0) | .filePath as $f | .messages[] | select(.severity == 2) | select(.ruleId != null) | [$f, (.line|tostring), .ruleId, (.message | split("\n") | first)] | join($sep)' \
    | grep -v "__tests__" \
    | grep -v "\.test\.ts" \
    | grep -v "\.spec\.ts" \
    | grep -v "__generated__" \
    | grep -v "generated" \
    | grep -v "graphql\.ts" \
    | awk -F"$SEP" '!seen[$1]++' \
    | head -20)

  if [ -z "$DETECTIONS" ]; then
    log "  ℹ️  除外後は検出なし"
    continue
  fi

  while IFS=$'\x01' read -r file line rule message; do
    short_file="${file#$DIR/}"

    if issue_exists "$EXISTING" "${short_file##src/}"; then
      log "  ⏭️  スキップ（既存Issue）: $short_file"
      continue
    fi

    log "  🤖 Issue生成中: $short_file:$line ($rule)"
    BODY_CONTENT=$(generate_issue_body "$short_file" "$line" "$rule: $message" "eslint")

    # 生成失敗時はスキップ
    if [ "$BODY_CONTENT" = "※ AI分析生成失敗。手動で確認してください。" ]; then
      log "  ⚠️  生成失敗のためスキップ: $short_file:$line"
      continue
    fi

    TITLE="[Refactor] ESLint: $rule in ${short_file##src/}"
    BODY="## 場所\n\`$short_file:$line\`\n\n## ESLintルール\n\`$rule\`\n\n## エラー内容\n$message\n\n$BODY_CONTENT\n\n---\n_自動検出: eslint agent ($DATE)_"

    # [L-2] echo -e の代わりに printf で確実に改行展開
    gh issue create \
      --repo "$REPO" \
      --title "$TITLE" \
      --body "$(printf '%b' "$BODY")" \
      --label "$LABELS" \
      2>>"$LOG_FILE" \
      && log "  ✅ 起票: $TITLE" \
      || log "  ⚠️  起票失敗: $TITLE (詳細: $LOG_FILE)"
  done <<< "$DETECTIONS"

  log "✅ [$REPO] ESLint検出 完了"
done
