# devops Makefile
# 使用方法: make <ターゲット>

REPO_ROOT := $(shell cd "$(dir $(lastword $(MAKEFILE_LIST)))" && pwd)
AUDIT_DIR := $(REPO_ROOT)/audit
SUGGEST_DIR := $(REPO_ROOT)/suggest
LOG_DIR := $(AUDIT_DIR)/logs
TODAY := $(shell date +"%Y-%m-%d")

.PHONY: audit suggest health logs clean-logs help

## audit: nightly-audit.sh を手動実行
audit:
	@echo "🚀 nightly-audit を実行中..."
	@bash "$(AUDIT_DIR)/nightly-audit.sh"

## suggest: code-quality.sh を手動実行（suggest + PR自動作成）
suggest:
	@echo "🚀 code-quality suggest を実行中..."
	@bash "$(SUGGEST_DIR)/code-quality.sh"

## health: Ollama接続・ANTHROPIC_API_KEY・gh auth を確認
health:
	@echo "=== ヘルスチェック ==="
	@echo -n "Ollama 接続: "
	@if curl -sf "http://127.0.0.1:11434/api/tags" > /dev/null 2>&1; then \
		echo "✅ OK"; \
	else \
		echo "❌ NG（Ollamaが起動していません）"; \
	fi
	@echo -n "ANTHROPIC_API_KEY: "
	@if [[ -n "$${ANTHROPIC_API_KEY:-}" ]]; then \
		echo "✅ 設定済み"; \
	else \
		echo "❌ 未設定（~/.zshrc に export ANTHROPIC_API_KEY=... を追加してください）"; \
	fi
	@echo -n "gh auth: "
	@if gh auth status > /dev/null 2>&1; then \
		echo "✅ 認証済み"; \
	else \
		echo "❌ 未認証（gh auth login を実行してください）"; \
	fi

## logs: 本日の監査ログを表示
logs:
	@LOG_FILE="$(LOG_DIR)/$(TODAY).log"; \
	if [[ -f "$$LOG_FILE" ]]; then \
		cat "$$LOG_FILE"; \
	else \
		echo "本日のログがありません: $$LOG_FILE"; \
	fi

## clean-logs: 30日以上前のログを削除
clean-logs:
	@echo "30日以上前のログを削除中..."
	@find "$(LOG_DIR)" -name "*.log" -mtime +30 -delete 2>/dev/null && echo "✅ 完了" || echo "ℹ️  削除対象なし"

## help: 使用可能なターゲット一覧を表示
help:
	@echo "使用可能なターゲット:"
	@grep -E '^## ' $(MAKEFILE_LIST) | sed 's/## /  make /'
