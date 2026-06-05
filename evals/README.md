# evals — 見積書抽出フローの LLMOps 評価

Dify の見積書抽出ワークフローを **Dify API 経由**で実行し、正解 JSON との **フィールド一致**で採点、
表記ゆれは **LLM-as-judge（gpt-4.1）**で救済、結果を **Langfuse** に記録する評価ハーネス。

## 構成

```
evals/
├── pyproject.toml            # uv プロジェクト（requests / openai / langfuse）
├── .env.example              # 接続情報テンプレート（.env はコミットしない）
├── dataset/ground_truth.json # 5 見積書の正解データ
├── quote_eval/
│   ├── config.py             # 環境変数
│   ├── normalize.py          # 数値/日付/文字列の正規化
│   ├── metrics.py            # フィールド採点（決定的）
│   ├── dify_client.py        # Dify API（ファイルUP→workflow実行）
│   ├── judge.py              # LLM-as-judge（Azure OpenAI）
│   ├── langfuse_logger.py    # Langfuse 記録（任意）
│   └── run_eval.py           # ランナー（CLI）
├── tests/test_metrics.py     # 決定的ロジックのユニットテスト
└── results/latest.json       # 実行結果（gitignore）
```

## 前提（Dify 側）

1. 見積書抽出ワークフローを作成（開始[file] → ドキュメント抽出 → パラメータ抽出[gpt-4.1] → 終了）。
2. **アプリを公開**し、「API アクセス」で **API キー**を発行。
3. 終了ノードは抽出項目を `quote_no/issue_date/valid_until/customer/vendor/subject/subtotal/tax/total/line_items`
   の名前で出力（または単一オブジェクト `result`）。`coerce_fields` が両形式を吸収します。

## セットアップ & 実行

```bash
cd evals
cp .env.example .env   # DIFY_API_BASE/KEY, AZURE_OPENAI_*, LANGFUSE_* を記入
uv sync                # 依存解決

# ユニットテスト（外部不要）
uv run pytest -q

# 実フロー評価（5 PDF を Dify で抽出して採点 → Langfuse 記録）
uv run python -m quote_eval.run_eval
# オプション: --no-langfuse / --no-judge / --samples techwave
```

## 採点方法

- **スカラ項目**（quote_no/日付/会社名/件名/金額）: 正規化して完全一致。日付は和暦・スラッシュも YYYY-MM-DD に統一して比較。
- **テキスト項目**（customer/vendor/subject）: 不一致なら **LLM-judge** が意味同値か再判定して救済。
- **明細(line_items)**: 件数一致と金額合計一致の平均（簡易）。
- **全体スコア** が `PASS_THRESHOLD`（既定 0.8）未満なら終了コード 1（CI 失敗）。

## CI

`.github/workflows/evals.yml`:
- **unit**: push/PR で常時（シークレット不要）。
- **eval**: 週次 schedule / 手動実行で実フロー評価（要 GitHub Secrets: `DIFY_API_BASE` `DIFY_API_KEY` `AZURE_OPENAI_*` `LANGFUSE_*`）。

## 今後の拡張

- 正解データ・サンプルPDFを増やしてカバレッジ拡大。
- プロンプト変更時の回帰をスコア推移（Langfuse）で監視。
- 明細の項目単位（品名・数量・単価）一致など採点粒度の強化。
