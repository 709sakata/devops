#!/bin/bash
# agents/complexity.sh
# 行数20行以上 or ネスト3段以上の関数を検出し、LLMに分割案を提示させてIssue起票
#
# 引数:
#   $1: repo (例: Hopin-inc/civicship-api)
#   $2: repo_dir (ローカルパス)

set -euo pipefail

# [C-1] SCRIPT_DIR をスクリプト自身のパスから動的に解決（ハードコード廃止）
SCRIPT_DIR="$(cd "$(dirname "$(realpath "$0")")" && pwd)"
source "${SCRIPT_DIR}/../../audit/agents/common.sh"

REPO="$1"
REPO_DIR="$2"
REPO_NAME="$(basename "$REPO")"

MAX_LINES=20
MAX_NEST=3
MAX_ISSUES=10

log "[$REPO_NAME] complexity: 開始"


detect() {
  local src_dir="${REPO_DIR}/src"
  [[ -d "$src_dir" ]] || { log "[$REPO_NAME] src/ が見つかりません"; return; }

  while IFS= read -r file; do
    local in_func=0 func_start=0 func_name="" func_lines=0
    local max_nest=0 brace_depth=0

    while IFS= read -r numbered_line; do
      lineno="${numbered_line%%:*}"
      content="${numbered_line#*:}"

      if echo "$content" | grep -qE "^export (async )?function |^export const [A-Za-z_][A-Za-z0-9_]* = (async )?\("; then
        in_func=1
        func_start="$lineno"
        func_lines=0
        max_nest=0
        brace_depth=0
        func_name="$(echo "$content" \
          | sed -E 's/.*export (async )?function ([A-Za-z_][A-Za-z0-9_]*).*/\2/' \
          | sed -E 's/.*export const ([A-Za-z_][A-Za-z0-9_]*) =.*/\1/')"
      fi

      if [[ $in_func -eq 1 ]]; then
        func_lines=$((func_lines + 1))
        opens="$(echo "$content" | tr -cd '{' | wc -c)"
        closes="$(echo "$content" | tr -cd '}' | wc -c)"
        brace_depth=$((brace_depth + opens - closes))
        [[ $brace_depth -gt $max_nest ]] && max_nest=$brace_depth

        if [[ $brace_depth -le 0 && $func_lines -gt 1 ]]; then
          if [[ $func_lines -ge $MAX_LINES || $max_nest -ge $MAX_NEST ]]; then
            rel="${file#"${REPO_DIR}/"}"
            echo "${rel}:${func_start}:${func_name}:${func_lines}:${max_nest}"
          fi
          in_func=0
        fi
      fi
    done < <(grep -n "" "$file" 2>/dev/null)
  done < <(find "$src_dir" \( -name "*.ts" -o -name "*.tsx" \) 2>/dev/null | grep -v "__tests__" | grep -v "__generated__" | sort | head -50)
}

findings=()
while IFS= read -r line; do findings+=("$line"); done < <(detect) || true

if [[ ${#findings[@]} -eq 0 ]]; then
  log "[$REPO_NAME] complexity: 検出なし、スキップ"
  exit 0
fi

table_rows=""
func_details=""
count=0
for entry in "${findings[@]}"; do
  [[ $count -ge $MAX_ISSUES ]] && break
  rel_path="$(echo "$entry" | cut -d: -f1)"
  start="$(echo    "$entry" | cut -d: -f2)"
  name="$(echo     "$entry" | cut -d: -f3)"
  lines="$(echo    "$entry" | cut -d: -f4)"
  nest="$(echo     "$entry" | cut -d: -f5)"

  # 関数の実コードを抽出（最大40行）
  # [H-3] off-by-one 修正: 終端行は start + lines - 1（start が func_lines に含まれるため）
  full_path="${REPO_DIR}/${rel_path}"
  func_code=""
  if [[ -f "$full_path" ]]; then
    func_code="$(sed -n "${start},$((start + lines - 1))p" "$full_path" | head -40)"
  fi

  table_rows+="| \`${rel_path}:${start}\` | \`${name}\` | ${lines} | ${nest} |\n"
  func_details+="### ${name}（${rel_path}:${start}、${lines}行、最大ネスト${nest}段）\n\`\`\`typescript\n${func_code}\n\`\`\`\n\n"
  count=$((count + 1))
done

prompt="以下のTypeScript関数は行数またはネストが深く、リファクタリングが推奨されます。
実装内容に基づき、以下のような手法を参考に具体的な改善方針を提案してください：
- 処理の抽出（Extract Function）
- 条件の簡略化（早期リターン、ガード節）
- 責務の分離（単一責任の原則）

${func_details}

前置き・後書き不要。各関数について「関数名: 提案内容」の形式で日本語で答えてください。"

suggestion="$(call_ollama "$prompt")"

total="${#findings[@]}"
body="## 🔀 複雑関数の検出\n\n"
body+="行数 **${MAX_LINES}行以上** または ネスト **${MAX_NEST}段以上** の関数です。\n\n"
body+="| ファイル | 関数名 | 行数 | 最大ネスト |\n"
body+="|---|---|---|---|\n"
body+="${table_rows}"
[[ $total -gt $MAX_ISSUES ]] && body+="\n_他 $((total - MAX_ISSUES)) 件省略_\n"
body+="\n### 💡 分割・改善提案\n\n${suggestion}\n"

title="[suggest] 複雑関数 (${REPO_NAME})"

existing_titles="$(get_existing_titles "$REPO")"
if issue_exists "$existing_titles" "$title"; then
  log "[$REPO_NAME] complexity: 既存Issueあり、スキップ"
  exit 0
fi

# [L-2] echo -e の代わりに printf で確実に改行展開
gh issue create \
  --repo "$REPO" \
  --title "$title" \
  --body "$(printf '%b' "$body")" \
  --label "refactor" \
  --label "Priority: Low"

log "[$REPO_NAME] complexity: Issue起票完了"
