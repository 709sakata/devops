#!/bin/bash
# agents/naming.sh
# ファイル単位で関数名一覧をLLMに渡し、意図が不明瞭な命名を指摘してIssue起票
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
# [P2-1] MAX_NAMING_FILES を config.sh の定数で統一
MAX_FILES="$MAX_NAMING_FILES"

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
次の観点で問題のある関数名を最大10件ピックアップし、改善案と理由を日本語で示してください：
- 名前が短すぎる・省略しすぎ（例: handle, proc, doIt）
- 動詞がない・意味が広すぎる（例: data, info, manager）
- 否定形や二重否定で意図が読みにくい
- ドメイン用語と乖離している

問題のない関数名は無視し、改善候補がなければ「改善候補なし」とだけ返してください。

${func_list}

前置き・後書き不要。改善候補がある場合は「元の名前 → 改善案: 理由」の形式で答えてください。"

result="$(call_ollama "$prompt")"

# [M-7] Ollama が空文字を返した場合もスキップ
if [[ -z "$result" ]]; then
  log "[$REPO_NAME] naming: AI応答なし、スキップ"
  exit 0
fi

# [M-7] 「改善候補なし」の判定パターンを限定的に（過剰マッチを防止）
if echo "$result" | grep -qiE "^改善候補なし$"; then
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

# [P4] create_issue 共通関数で起票
create_issue "$REPO" "$title" "$body" "refactor" "Priority: Low"

log "[$REPO_NAME] naming: Issue起票完了"
