# devops

civicship-api / civicship-portal のコード品質を自動監視・改善提案するスクリプト群。

## 構成
```
scripts/
├── audit/                    # 監視・アラート（nightly-audit）
│   ├── nightly-audit.sh      # オーケストレーター（毎日0時）
│   └── agents/
│       ├── common.sh         # 共通関数
│       ├── security.sh       # 脆弱性パッケージ検出（毎日）
│       ├── type-safety.sh    # any型の乱用検出（月水金）
│       └── eslint.sh         # ESLintエラー検出（月水金）
│
└── suggest/                  # 改善提案・PR自動作成
    ├── code-quality.sh       # オーケストレーター（毎週月曜3時）
    └── agents/
        ├── common.sh         → audit/agents/common.sh を流用
        ├── uncommented.sh    # JSDocなし関数を検出・自動生成
        ├── naming.sh         # 命名レビュー
        ├── complexity.sh     # 複雑関数検出
        └── pr-creator.sh     # Issueをまとめて修正PRを自動作成
```

## 実行環境

- MacBook Air → SSHトンネル → Mac Mini（Ollama）
- Ollama モデル: `qwen2.5-coder:7b`（audit / suggest用）
- Claude API: `claude-sonnet-4-20250514`（pr-creator用）

## crontab
```
# nightly-audit（毎日0時）
0 0 * * * ~/scripts/audit/nightly-audit.sh >> ~/scripts/audit/logs/$(date +\%Y-\%m-\%d).log 2>&1

# code-quality suggest（毎週月曜3時）
0 3 * * 1 ~/scripts/suggest/code-quality.sh >> ~/scripts/suggest/logs/code-quality.log 2>&1
```

## 環境変数
```bash
export ANTHROPIC_API_KEY="sk-ant-..."
```

## GitHub Issues ラベル体系

| ラベル | 意味 |
|--------|------|
| `refactor` | リファクタリング対象 |
| `security` | セキュリティ関連 |
| `Priority: Low` | 優先度低 |
| `Problem: Security` | セキュリティ問題 |
