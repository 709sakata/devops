#!/bin/bash
# agents/uncommented.sh
# export関数の直前にJSDocがないものを検出し、LLMにJSDocを生成させてIssue起票
#
# 引数:
#   $1: repo (例: Hopin-inc/civicship-api)
#   $2: repo_dir (ローカルパス)

set -euo pipefail

source "${HOME}/scripts/devops/audit/agents/common.sh"

REPO="$1"
REPO_DIR="$2"
REPO_NAME="$(basename "$REPO")"
MAX_ISSUES=10

log "[$REPO_NAME] uncommented: 開始"

# ----------------------------------------------------------
# コメントなし関数を検出
# 戻り値: "相対パス:行番号:関数シグネチャ" の行リスト
# ----------------------------------------------------------
detect() {
  local src_dir="${REPO_DIR}/src"
  [[ -d "$src_dir" ]] || { log "[$REPO_NAME] src/ が見つかりません"; return; }

  grep -rn --include="*.ts" --include="*.tsx" \
    --exclude-dir="__tests__" --exclude-dir="__generated__" \
    -E "^export (async )?function |^export const [A-Za-z_][A-Za-z0-9_]* = (async )?\(" \
    "$src_dir" 2>/dev/null \
  | head -60 \
  | while IFS=: read -r file lineno rest; do
      prev=""
      [[ "$lineno" -gt 1 ]] && prev="$(sed -n "$((lineno - 1))p" "$file")"
      if ! echo "$prev" | grep -qE '^\s*(//|\*|/\*)'; then
        rel="${file#"${REPO_DIR}/"}"
        echo "${rel}:${lineno}:${rest}"
      fi
    done
}

# ----------------------------------------------------------
# メイン
# ----------------------------------------------------------

# Ollamaへの汎用呼び出し（common.shのgenerate_issue_bodyとは別用途）
mapfile -t findings < <(detect) || true

if [[ ${#findings[@]} -eq 0 ]]; then
  log "[$REPO_NAME] uncommented: 検出なし、スキップ"
  exit 0
fi

body="## 📝 JSDocコメントがない関数\n\n"
body+="以下の関数にJSDocがありません。生成済みのコメントをそのままコピペできます。\n\n"

count=0
for entry in "${findings[@]}"; do
  [[ $count -ge $MAX_ISSUES ]] && break
  rel_path="$(echo "$entry" | cut -d: -f1)"
  lineno="$(echo  "$entry" | cut -d: -f2)"
  func_sig="$(echo "$entry" | cut -d: -f3-)"

  prompt="以下のTypeScript関数シグネチャに対してJSDocコメントを生成してください。
@description・@param・@returnsを含め、JSDocコメントのみ出力してください。
前置き・コードブロック・バッククォートは不要です。

${func_sig}"

  jsdoc="$(call_ollama "$prompt" | grep -v "^\`\`\`")"

  body+="### \`${rel_path}:${lineno}\`\n\`\`\`typescript\n${jsdoc}\n${func_sig}\n\`\`\`\n\n"
  count=$((count + 1))
done

total="${#findings[@]}"
[[ $total -gt $MAX_ISSUES ]] && body+="_他 $((total - MAX_ISSUES)) 件省略_\n\n"

title="[suggest] JSDocなし関数 (${REPO_NAME})"

existing_titles="$(get_existing_titles "$REPO")"
if issue_exists "$existing_titles" "$title"; then
  log "[$REPO_NAME] uncommented: 既存Issueあり、スキップ"
  exit 0
fi

# [L-2] echo -e の代わりに printf で確実に改行展開
gh issue create \
  --repo "$REPO" \
  --title "$title" \
  --body "$(printf '%b' "$body")" \
  --label "refactor" \
  --label "Priority: Low"

log "[$REPO_NAME] uncommented: Issue起票完了"
