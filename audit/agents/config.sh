#!/bin/bash
# shellcheck shell=bash
# ============================================================
# config.sh — 全スクリプト共通定数（変更はここのみ）
# common.sh から source される。直接実行不可。
# ============================================================

# ----------------------------------------------------------
# モデル設定（環境変数でオーバーライド可能）
# ----------------------------------------------------------
# [P2-1] ハードコードを廃止。環境変数があればそちらを優先
readonly OLLAMA_MODEL="${OLLAMA_MODEL_OVERRIDE:-qwen2.5-coder:7b}"
readonly CLAUDE_MODEL="${CLAUDE_MODEL_OVERRIDE:-claude-sonnet-4-6}"
readonly OLLAMA_URL="http://127.0.0.1:11434/api/generate"

# ----------------------------------------------------------
# タイムアウト（秒）
# ----------------------------------------------------------
readonly OLLAMA_TIMEOUT_SHORT=30   # generate_issue_body 用（短いプロンプト）
readonly OLLAMA_TIMEOUT_LONG=60    # call_ollama 用（長いプロンプト）
readonly CLAUDE_TIMEOUT=120        # Claude API 用（PR本文生成等）

# ----------------------------------------------------------
# 検出上限（根拠をコメントで明示）
# ----------------------------------------------------------
# Issue 本文が GitHub の表示上限を超えないよう制限
readonly MAX_ANY_TYPE_FILES=10
# ESLint 結果が多すぎる場合のノイズ抑制（1ファイル1エラーのみ）
readonly MAX_ESLINT_FILES=20
# Ollama の num_predict=400 トークンに収まる行数
readonly MAX_DEAD_CODE_LINES=60
# 同上（複雑関数検出）
readonly MAX_COMPLEXITY_LINES=40
# PR 差分が大きくなりすぎてレビュー負荷が上がらないよう制限
readonly MAX_SUGGEST_FILES=10
# 命名レビュー対象（ファイル数が多いと Ollama のコンテキスト超過）
readonly MAX_NAMING_FILES=15
