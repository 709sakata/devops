#!/bin/bash
# ============================================================
# 🔒 security.sh
# Dependabotアラート検出 → 使用箇所評価 → Issue起票
# 実行頻度: 毎晩
# ============================================================

source "$(dirname "$0")/common.sh"

# パッケージの実際の使用箇所をsrc/から検索
get_package_usages() {
  local pkg="$1"
  local dir="$2"

  grep -rn "from ['\"]${pkg}\|require(['\"]${pkg}" "$dir/src/" \
    --include="*.ts" --include="*.tsx" \
    | grep -v "__tests__" \
    | grep -v "\.test\.ts" \
    | grep -v "\.spec\.ts" \
    | grep -v "node_modules" \
    | head -10
}

# 使用箇所をOllamaにリスク評価させる
evaluate_usage_risk() {
  local pkg="$1"
  local vuln="$2"
  local usages="$3"

  if [ -z "$usages" ]; then
    echo "リスク評価: 低（src/内での直接使用箇所なし・トランジティブ依存の可能性）"
    return
  fi

  local response
  response=$(curl -s --max-time 30 "$OLLAMA_URL" \
    -H "Content-Type: application/json" \
    -d "{
      \"model\": \"$OLLAMA_MODEL\",
      \"prompt\": $(echo "パッケージ「${pkg}」の脆弱性「${vuln}」について評価してください。
以下の使用箇所からユーザー入力が流れ込むリスクを判断してください：

${usages}

以下の形式で答えてください：
リスク評価: 高/中/低
理由: （1文）" | jq -Rs .),
      \"stream\": false,
      \"options\": { \"temperature\": 0.1, \"num_ctx\": 1024, \"num_predict\": 100 }
    }" | jq -r '.response // ""')

  if [ -z "$response" ]; then
    echo "リスク評価: 不明（AI分析失敗）"
  else
    echo "$response"
  fi
}

for i in "${!REPOS[@]}"; do
  REPO="${REPOS[$i]}"
  DIR="${REPO_DIRS[$i]}"

  log "🔒 [$REPO] Dependabotセキュリティアラート監査..."

  EXISTING=$(get_existing_titles "$REPO")

  gh api repos/$REPO/dependabot/alerts \
    --jq '.[] | select(.state == "open") | [
      .dependency.package.name,
      .security_advisory.severity,
      (.security_vulnerability.first_patched_version.identifier // "不明"),
      .security_advisory.summary
    ] | join("|")' \
    | cat \
    | awk -F'|' '!seen[$1]++' \
    | while IFS='|' read -r package severity fixed_in summary; do

        # lowはスキップ
        if [[ "$severity" == "low" ]]; then
          log "  ⏭️  スキップ（low severity）: $package"
          continue
        fi

        TITLE="[Security] $package - $summary"

        if issue_exists "$EXISTING" "$package"; then
          log "  ⏭️  スキップ（既存Issue）: $package"
          continue
        fi

        # 使用箇所を検索
        log "  🔍 使用箇所を検索中: $package"
        USAGES=$(get_package_usages "$package" "$DIR")

        # リスク評価
        log "  🤖 リスク評価中: $package ($severity)"
        RISK_EVAL=$(evaluate_usage_risk "$package" "$summary" "$USAGES")

        # Issueボディ生成
        BODY_CONTENT=$(generate_issue_body "$package" "$fixed_in" "$summary" "security")

        # 使用箇所セクション
        if [ -z "$USAGES" ]; then
          USAGE_SECTION="src/内での直接使用箇所なし（トランジティブ依存の可能性あり）"
        else
          USAGE_SECTION="\`\`\`\n$USAGES\n\`\`\`"
        fi

        # ラベル判断
        if [[ "$severity" == "critical" || "$severity" == "high" ]]; then
          LABELS=$(resolve_labels "security_high")
        else
          LABELS=$(resolve_labels "security_medium")
        fi

        BODY="## パッケージ\n\`$package\`\n\n## 深刻度\n$severity\n\n## 修正バージョン\n\`$fixed_in\`\n\n$BODY_CONTENT\n\n## 使用箇所\n$USAGE_SECTION\n\n## リスク評価\n$RISK_EVAL\n\n---\n_自動検出: security agent ($DATE)_"

        gh issue create \
          --repo "$REPO" \
          --title "$TITLE" \
          --body "$(echo -e "$BODY")" \
          --label "$LABELS" \
          2>>"$LOG_FILE" \
          && log "  ✅ 起票: $TITLE [$severity]" \
          || log "  ⚠️  起票失敗: $TITLE (詳細: $LOG_FILE)"
      done

  log "✅ [$REPO] Dependabotセキュリティアラート監査 完了"
done
