# devops

GitHubリポジトリのコード品質を自動監視・改善提案するスクリプト群。
対象リポジトリは `audit/agents/common.sh` の `REPOS` / `REPO_DIRS` で設定（デフォルト: civicship-api / civicship-portal）。

## アーキテクチャ
```
Mac Mini（常時稼働）
  ├── cron で自動実行
  ├── Ollama（qwen2.5-coder:7b）をローカル実行
  └── ghq で GitHub からスクリプトを管理

MacBook Air
  └── スクリプトを編集して push するだけ
      → Mac Mini が毎日 2時に git pull で自動反映
```

## ディレクトリ構成
```
scripts/
├── audit/                    # 監視・アラート
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
        ├── uncommented.sh    # JSDocなし関数を検出・自動生成
        ├── naming.sh         # 命名レビュー
        ├── complexity.sh     # 複雑関数検出
        └── pr-creator.sh     # Issueをまとめて修正PRを自動作成
```

## cron（Mac Mini）
```
0 2 * * *   git pull origin main（スクリプト自動更新）
0 0 * * *   nightly-audit.sh（毎日0時）
0 3 * * 1   code-quality.sh（毎週月曜3時）
```

## 環境変数（Mac Mini の ~/.zshrc）
```bash
export ANTHROPIC_API_KEY="sk-ant-..."
```

## 使用モデル

| 用途 | モデル |
|------|--------|
| audit / suggest（検出・分析） | Ollama: `qwen2.5-coder:7b` |
| pr-creator（コード修正・PR作成） | Claude API: `claude-sonnet-4-20250514` |
