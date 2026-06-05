# 本番トレースへの品質スコア付与（オンライン評価）

Dify の本番実行トレースは Langfuse に自動記録されるが、記録されるのは **入出力・トークン・コスト・レイテンシ** までで、
「抽出が正しかったか」の **品質スコアは自動では付かない**。本番では「正解データ」が手元に無いため、
正解と突き合わせる採点（オフライン評価）ができないからである。

そこで本番品質を数値で測るのが **オンライン評価**。基本の流れは次のとおり。

```
本番トレースを Langfuse から取得 → 評価 → スコアを Langfuse に書き戻す
                                    ↑ 評価のやり方が2種類ある
```

---

## 評価の2方式

| 方式 | LLM を使う？ | 向くチェック |
|---|---|---|
| **A. LLM-as-judge** | ✅ 使う | 主観的・意味的（例: 件名が内容と合っているか、要約の質） |
| **B. 決定的スコアラー（コード）** | ❌ 使わない | 形式・検算・非空（例: JSON 妥当性、`total = subtotal + tax`、必須項目の充足） |

> 重要: 「必須9項目が非空」「total=subtotal+tax」「JSON 妥当か」は **すべてコードで判定でき、LLM は不要**。
> LLM に「1+1 は合っているか」を聞くようなもので過剰。**LLM-as-judge は「正解も無く・ルールでも測れない意味的判断」専用**と考える。

---

## 方式A：Langfuse の LLM-as-judge（意味的チェック用）

Langfuse Cloud の UI で設定（コード不要・Langfuse がトレースに自動採点）。

1. **Settings → LLM Connections** に Azure OpenAI（gpt-4.1）を登録
2. **Evaluators / Evaluations** で評価器を作成
   - 対象トレース（アプリ）とサンプリング率を指定
   - 採点プロンプト（例:「この抽出結果は妥当か 0〜1 で採点」）
   - トレースの `output` を judge へマッピング
3. 以後、本番トレース（サンプル）に自動でスコアが付与される

- メリット: 人手不要・常時監視。
- 注意: LLM 課金が発生し非決定的。コスト抑制のため **サンプリング**して一部だけ採点するのが一般的。

---

## 方式B：決定的スコアラー（推奨・ルールベース）

本番トレースを取得 → コードでルール判定 → スコアを書き戻す。**無料・確実・再現可能**。

### スコア項目（例）

| スコア名 | 内容 | 判定 |
|---|---|---|
| `json_valid` | 出力が妥当な JSON か | `json.loads` 可否 |
| `required_filled` | 必須9項目が非空の割合 | 空でない項目数 / 9 |
| `total_consistent` | `total = subtotal + tax` の検算 | 一致で 1.0 |
| `line_items_sum_ok` | 明細の金額合計 = 小計 | 一致で 1.0 |

### サンプルコード

```python
from langfuse import Langfuse
from quote_eval.dify_client import coerce_fields  # 既存の JSON 抽出を再利用

lf = Langfuse()  # .env のキー（LANGFUSE_PUBLIC_KEY / SECRET_KEY / HOST）

REQUIRED = ["quote_no", "issue_date", "customer", "vendor", "subject",
            "subtotal", "tax", "total", "line_items"]

# 直近の本番トレースを取得（重複採点回避は from_timestamp 等で）
for t in lf.fetch_traces(limit=50).data:
    pred = coerce_fields(t.output if isinstance(t.output, dict) else {"text": t.output})

    json_valid = 1.0 if pred else 0.0
    filled = (sum(1 for k in REQUIRED
                  if pred.get(k) not in (None, "", [], 0)) / len(REQUIRED)) if pred else 0.0
    total_ok = 1.0 if pred and pred.get("total") == (pred.get("subtotal", 0) + pred.get("tax", 0)) else 0.0
    items_sum = sum((i.get("amount") or 0) for i in (pred.get("line_items") or [])) if pred else 0
    items_ok = 1.0 if pred and items_sum == pred.get("subtotal") else 0.0

    for name, val in [("json_valid", json_valid), ("required_filled", filled),
                      ("total_consistent", total_ok), ("line_items_sum_ok", items_ok)]:
        lf.score(trace_id=t.id, name=name, value=val)

lf.flush()
```

### これで得られるもの
- 本番トレース1件ごとにスコアが付き、Langfuse のダッシュボードで
  **「形式エラー率」「項目欠落率」「検算NG率」の推移**が見えるようになる。
- **正解データ無しで本番品質を数値監視**できる（＝オンライン評価の核心）。

### 定期実行（どちらか）
- **VM の cron**（例: 15分ごと）— 本番に近く運用が簡単
- **GitHub Actions の schedule** — 既存 CI に相乗り

### 重複採点を避ける
- 取得時に `from_timestamp`（前回実行以降）で絞る、または既にスコアのあるトレースは skip する。

---

## 使い分けまとめ

- **形式・検算・非空（決定的に測れるもの）** → 方式B（コード、LLM不要）
- **意味的な妥当性（主観的なもの）** → 方式A（LLM-as-judge）
- 両方を同じ Langfuse プロジェクトに集約すると、本番品質を多角的に監視できる。

## オフライン評価との関係

| | データ | きっかけ | 用途 |
|---|---|---|---|
| オンライン評価（本書） | 正解なし（本番の実データ） | ユーザーのアプリ実行 | 本番品質の常時監視 |
| オフライン評価（`evals/run_eval`） | 正解あり（固定データセット） | 手動 / CI | 変更時の回帰検知 |

両者を併用することで「本番の実挙動」と「リリース前の回帰チェック」の両面をカバーできる。
