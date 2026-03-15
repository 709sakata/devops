#!/bin/bash
# shellcheck shell=bash
# ============================================================
# tests/test_common.sh — パースロジックの単体テスト
# 外部依存なし（bash のみ）。CI や make test で実行可能。
# ============================================================

set -euo pipefail

PASS=0
FAIL=0

assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    PASS=$((PASS + 1))
    printf "  PASS: %s\n" "$desc"
  else
    FAIL=$((FAIL + 1))
    printf "  FAIL: %s\n    expected: [%s]\n    actual:   [%s]\n" \
      "$desc" "$expected" "$actual"
  fi
}

assert_match() {
  local desc="$1" pattern="$2" actual="$3"
  if echo "$actual" | grep -qE "$pattern"; then
    PASS=$((PASS + 1))
    printf "  PASS: %s\n" "$desc"
  else
    FAIL=$((FAIL + 1))
    printf "  FAIL: %s\n    pattern: [%s]\n    actual:  [%s]\n" \
      "$desc" "$pattern" "$actual"
  fi
}

# ----------------------------------------------------------
# common.sh を source（PATH・ログ設定が走る）
# ----------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "$(realpath "$0")")" && pwd)"
# shellcheck source=../audit/agents/common.sh
source "${SCRIPT_DIR}/../audit/agents/common.sh"

printf "=== common.sh のロード ===\n"
assert_eq "OLLAMA_MODEL が設定されている" "qwen2.5-coder:7b" "$OLLAMA_MODEL"
assert_eq "CLAUDE_MODEL が設定されている" "claude-sonnet-4-6" "$CLAUDE_MODEL"
assert_eq "OLLAMA_TIMEOUT_SHORT が設定されている" "30" "$OLLAMA_TIMEOUT_SHORT"
assert_eq "MAX_ESLINT_FILES が設定されている" "20" "$MAX_ESLINT_FILES"

# ----------------------------------------------------------
# resolve_labels テスト
# ----------------------------------------------------------
printf "\n=== resolve_labels ===\n"
assert_eq "any_type → refactor,Priority: Low" \
  "refactor,Priority: Low" \
  "$(resolve_labels "any_type")"

assert_eq "eslint → refactor,Priority: Low" \
  "refactor,Priority: Low" \
  "$(resolve_labels "eslint")"

assert_eq "security_high → Problem: Security,Priority: High" \
  "Problem: Security,Priority: High" \
  "$(resolve_labels "security_high")"

assert_eq "security_medium → Problem: Security,Priority: Low" \
  "Problem: Security,Priority: Low" \
  "$(resolve_labels "security_medium")"

assert_eq "deps → Type: Dependencies,Priority: Low" \
  "Type: Dependencies,Priority: Low" \
  "$(resolve_labels "deps")"

assert_eq "unknown → Type: Task" \
  "Type: Task" \
  "$(resolve_labels "unknown_type")"

# ----------------------------------------------------------
# issue_exists テスト
# ----------------------------------------------------------
printf "\n=== issue_exists ===\n"
EXISTING_TITLES=$'[Security] lodash - Prototype Pollution\n[Refactor] any型の乱用: src/foo.ts\n[suggest] JSDocなし関数 (civicship-api)'

assert_eq "完全一致: あり" "0" \
  "$(issue_exists "$EXISTING_TITLES" "[Security] lodash" && echo 0 || echo 1)"

assert_eq "部分一致: あり" "0" \
  "$(issue_exists "$EXISTING_TITLES" "any型の乱用" && echo 0 || echo 1)"

assert_eq "存在しない: なし" "1" \
  "$(issue_exists "$EXISTING_TITLES" "[Security] axios" && echo 0 || echo 1)"

assert_eq "空文字列: なし" "1" \
  "$(issue_exists "" "[Security] lodash" && echo 0 || echo 1)"

# ----------------------------------------------------------
# dead-code.sh のシンボル抽出ロジック（sed パターン）
# ----------------------------------------------------------
printf "\n=== シンボル抽出 (dead-code.sh sed パターン) ===\n"
extract_symbol() {
  echo "$1" | sed -E \
    's/^export (const|function|class|type|interface|enum) ([A-Za-z_][A-Za-z0-9_]*).*/\2/'
}

assert_eq "export function" \
  "myFunction" \
  "$(extract_symbol "export function myFunction(args): ReturnType {")"

assert_eq "export const" \
  "myConst" \
  "$(extract_symbol "export const myConst = async () => {")"

assert_eq "export class" \
  "MyClass" \
  "$(extract_symbol "export class MyClass implements Iface {")"

assert_eq "export type" \
  "MyType" \
  "$(extract_symbol "export type MyType = string | number")"

assert_eq "export interface" \
  "IMyInterface" \
  "$(extract_symbol "export interface IMyInterface {")"

# ----------------------------------------------------------
# require_command テスト
# ----------------------------------------------------------
printf "\n=== require_command ===\n"
assert_eq "bash は存在する" "0" \
  "$(require_command bash > /dev/null 2>&1 && echo 0 || echo 1)"

assert_eq "存在しないコマンドは 1 を返す" "1" \
  "$(require_command __nonexistent_cmd_xyz__ > /dev/null 2>&1 && echo 0 || echo 1)"

# ----------------------------------------------------------
# PATH に主要パスが含まれるか（setup_path が効いているか）
# ----------------------------------------------------------
printf "\n=== setup_path ===\n"
assert_match "/usr/local/bin は PATH に含まれる" "/usr/local/bin" "$PATH"

# ----------------------------------------------------------
# 結果サマリー
# ----------------------------------------------------------
printf "\n==============================\n"
printf "%d passed, %d failed\n" "$PASS" "$FAIL"
printf "==============================\n"

[[ $FAIL -eq 0 ]] || exit 1
