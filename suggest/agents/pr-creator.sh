#!/bin/bash
# agents/pr-creator.sh
# [suggest]系Issueをカテゴリ別にまとめてClaude APIでPR作成
#
# 使い方: bash pr-creator.sh <repo> <repo_dir>

set -euo pipefail

source "${HOME}/scripts/audit/agents/common.sh"

REPO="$1"
REPO_DIR="$2"
REPO_NAME="$(basename "$REPO")"
ANTHROPIC_API_KEY="${ANTHROPIC_API_KEY:-}"
CLAUDE_MODEL="claude-sonnet-4-20250514"
DATE=$(date +"%Y%m%d")

log "[$REPO_NAME] pr-creator: 開始"

# ----------------------------------------------------------
# Claude API呼び出し
# ----------------------------------------------------------
call_claude() {
  local system="$1"
  local user="$2"
  local raw
  raw=$(curl -s --max-time 120 "https://api.anthropic.com/v1/messages" \
    -H "Content-Type: application/json" \
    -H "x-api-key: $ANTHROPIC_API_KEY" \
    -H "anthropic-version: 2023-06-01" \
    -d "{
      \"model\": \"$CLAUDE_MODEL\",
      \"max_tokens\": 4096,
      \"system\": $(echo "$system" | jq -Rs .),
      \"messages\": [{\"role\": \"user\", \"content\": $(echo "$user" | jq -Rs .)}]
    }")
  echo "$raw" | jq -r '.content[0].text // ""' 2>/dev/null || echo ""
}

# ----------------------------------------------------------
# カテゴリ別にIssueを処理
# ----------------------------------------------------------
process_category() {
  local category="$1"      # jsdoc / complexity / naming
  local title_pattern="$2" # Issueタイトルの検索パターン
  local branch_prefix="$3" # ブランチ名のプレフィックス

  # 対象Issueを取得
  local issues
  issues=$(gh issue list \
    --repo "$REPO" \
    --state open \
    --label refactor \
    --json number,title,body \
    --jq "[.[] | select(.title | test(\"$title_pattern\"))]")

  local count
  count=$(echo "$issues" | jq length)

  if [[ "$count" -eq 0 ]]; then
    log "[$REPO_NAME] pr-creator[$category]: 対象Issueなし、スキップ"
    return
  fi

  log "[$REPO_NAME] pr-creator[$category]: ${count}件のIssueを処理"

  # Issue番号リストとbody結合
  local issue_numbers
  issue_numbers=$(echo "$issues" | jq -r '.[].number' | tr '\n' ' ')
  local combined_body
  combined_body=$(echo "$issues" | jq -r '.[] | "## Issue #\(.number): \(.title)\n\(.body)\n"')

  # 対象ファイルをIssue本文から抽出
  local files
  files=$(echo "$combined_body" | grep -oE 'src/[^`\s]+\.(ts|tsx)' | sort -u | head -20)

  if [[ -z "$files" ]]; then
    log "[$REPO_NAME] pr-creator[$category]: 対象ファイル抽出できず、スキップ"
    return
  fi

  # ファイル内容を収集
  local file_contents=""
  while IFS= read -r f; do
    local full_path="${REPO_DIR}/${f}"
    [[ -f "$full_path" ]] || continue
    file_contents+="### ${f}\n\`\`\`typescript\n$(cat "$full_path")\n\`\`\`\n\n"
  done <<< "$files"

  # Claude APIに修正を依頼
  local system
  system="あなたはTypeScriptのエキスパートエンジニアです。
指示されたコードの修正を行い、修正後のファイル内容をJSON形式で返してください。
必ず以下のJSON形式のみを返してください（前置き・説明不要）:
{
  \"files\": [
    {\"path\": \"src/xxx.ts\", \"content\": \"修正後の全内容\"},
    ...
  ],
  \"pr_title\": \"PRタイトル（日本語）\",
  \"pr_body\": \"PR説明（日本語、Markdownで記載、最後にCloses #番号を列挙）\"
}"

  local user
  user="以下のGitHub Issueの内容に従ってコードを修正してください。

## 修正対象Issue
${combined_body}

## 対象ファイルの現在の内容
${file_contents}

Issue番号: ${issue_numbers}
これらすべてのIssueをCloseするPRを作成してください。"

  log "[$REPO_NAME] pr-creator[$category]: Claude APIに修正依頼中..."
  local response
  response=$(call_claude "$system" "$user")

  # JSONをパース
  local pr_title pr_body
  pr_title=$(echo "$response" | jq -r '.pr_title // ""')
  pr_body=$(echo "$response" | jq -r '.pr_body // ""')
  local files_json
  files_json=$(echo "$response" | jq -r '.files // []')

  if [[ -z "$pr_title" ]] || [[ "$files_json" == "[]" ]]; then
    log "[$REPO_NAME] pr-creator[$category]: レスポンス解析失敗、スキップ"
    log "[$REPO_NAME] response: $response"
    return
  fi

  # ブランチ作成
  local branch="suggest/${branch_prefix}-${DATE}"
  cd "$REPO_DIR"
  git checkout master 2>/dev/null || git checkout main 2>/dev/null
  git pull origin master 2>/dev/null || git pull origin main 2>/dev/null
  git checkout -b "$branch"

  # ファイルを書き込み
  echo "$files_json" | jq -c '.[]' | while IFS= read -r file_obj; do
    local path content
    path=$(echo "$file_obj" | jq -r '.path')
    content=$(echo "$file_obj" | jq -r '.content')
    local full_path="${REPO_DIR}/${path}"
    echo "$content" > "$full_path"
    git add "$full_path"
    log "[$REPO_NAME] 修正適用: $path"
  done

  # コミット＆プッシュ
  git commit -m "suggest: ${pr_title}"
  git push origin "$branch"

  # PR作成
  gh pr create \
    --repo "$REPO" \
    --title "$pr_title" \
    --body "$pr_body" \
    --base master \
    --head "$branch" \
    --label "refactor" \
    --label "Priority: Low"

  log "[$REPO_NAME] pr-creator[$category]: PR作成完了"

  # 元のブランチに戻る
  git checkout master 2>/dev/null || git checkout main 2>/dev/null
}

# ----------------------------------------------------------
# 各カテゴリを処理
# ----------------------------------------------------------
process_category "jsdoc"       "JSDocなし関数"     "jsdoc"
process_category "complexity"  "複雑関数"           "complexity"
process_category "naming"      "命名改善候補あり"   "naming"

log "[$REPO_NAME] pr-creator: 完了"
