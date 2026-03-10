#!/bin/bash
# agents/naming.sh
# ファイル単位で関数名一覧をLLMに渡し、意図が不明瞭な命名を指摘してIssue起票
#
# 引数:
#   $1: repo (例: Hopin-inc/civicship-api)
#   $2: repo_dir (ローカルパス)

set -euo pipefail

source "${HOME}/scripts/audit/agents/common.sh"

REPO="$1"
REPO_DIR="$2"
REPO_NAME="$(basename "$REPO")"
MAX_FILES=15

log "[$REPO_NAME] naming: 開始"


collect_names() {
  local src_dir="${REPO_DIR}/src"
  [[ -d "$src_dir" ]] || { log "[$REPO_NAME] src/ が見つかりません"; return; }

  local count=0
  while IFS= read -r file; do
    [[ $count -ge $MAX_FILES ]] && break
    rel="${file#"${REPO_DIR}/"}"

    names="$(grep -E "^export (async )?function [A-Za-z_]|^export const [A-Za-z_][A-Za-z0-9_]* =" \
      "$file" 2>/dev/null \
      | sed -E 's/.*export (async )?function ([A-Za-z_][A-Za-z0-9_]*).*/\2/' \
      | sed -E 's/.*export const ([A-Za-z_][A-Za-z0-9_]*) =.*/\1/' \
      | tr '\n' ', ' | sed 's/,$//')"

    [[ -z "$names" ]] && continue
    echo "- ${rel}: ${names}"
    count=$((count + 1))
  done < <(find "$src_dir" \( -name "*.ts" -o -name "*.tsx" \) 2>/dev/null | grep -v "__tests__" | grep -v "__generated__" | sort | head -40)
}

func_list="$(collect_names)"

if [[ -z "$func_list" ]]; then
  log "[$REPO_NAME] naming: 関数名取得できず、スキップ"
  exit 0
fi

# プロジェクト種別をリポジトリ名から推定
project_context=""
case "$REPO_NAME" in
  *api*)   project_context="バックエンドAPI（NestJS想定）" ;;
  *portal* | *web* | *front*) project_context="フロントエンド（Next.js想定）" ;;
  *)       project_context="TypeScriptプロジェクト" ;;
esac

prompt="以下は${project_context}のファイルごとの関数名一覧です。
意図が不明瞭・曖昧・改善の余地がある関数名を最大10件ピックアップし、
改善案と理由を日本語で簡潔に示してください。
問題のない関数名は無視し、改善候補がなければ「改善候補なし」とだけ返してください。

${func_list}

必ず日本語で回答してください。前置き・後書き不要。改善候補がある場合は「元の名前 → 改善案: 理由」の形式で答えてください。"

result="$(call_ollama "$prompt")"

if echo "$result" | grep -qi "改善候補なし\|問題なし\|特になし"; then
  log "[$REPO_NAME] naming: 改善候補なし、スキップ"
  exit 0
fi

body="## 🏷️ 関数命名レビュー\n\n${result}\n"
title="[suggest] 命名改善候補あり (${REPO_NAME})"

existing_titles="$(get_existing_titles "$REPO")"
if issue_exists "$existing_titles" "$title"; then
  log "[$REPO_NAME] naming: 既存Issueあり、スキップ"
  exit 0
fi

gh issue create \
  --repo "$REPO" \
  --title "$title" \
  --body "$(echo -e "$body")" \
  --label "refactor" \
  --label "Priority: Low"

log "[$REPO_NAME] naming: Issue起票完了"
