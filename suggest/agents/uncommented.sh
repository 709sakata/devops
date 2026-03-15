#!/bin/bash
# agents/uncommented.sh
# export関数の直前にJSDocがないものを検出し、LLMにJSDocを生成させてIssue起票
#
# 引数:
#   $1: repo (例: Hopin-inc/civicship-api)
#   $2: repo_dir (ローカルパス)

set -euo pipefail

# [C-1] SCRIPT_DIR をスクリプト自身のパスから動的に解決（ハードコード廃止）
SCRIPT_DIR="$(cd "$(dirname "$(realpath "$0")")" && pwd)"
# shellcheck source=../../audit/agents/common.sh
source "${SCRIPT_DIR}/../../audit/agents/common.sh"

# [P0-2] 必須コマンドの事前検証
require_command gh || exit 1

REPO="$1"
REPO_DIR="$2"
REPO_NAME="$(basename "$REPO")"
# [P2-1] MAX_SUGGEST_FILES を config.sh の定数で統一
MAX_ISSUES="$MAX_SUGGEST_FILES"

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
  | head -"$MAX_DEAD_CODE_LINES" \
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
findings=()
while IFS= read -r line; do findings+=("$line"); done < <(detect) || true

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

# [P4] create_issue 共通関数で起票
create_issue "$REPO" "$title" "$body" "refactor" "Priority: Low"

log "[$REPO_NAME] uncommented: Issue起票完了"
