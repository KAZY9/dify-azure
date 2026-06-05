"""決定的ロジックのユニットテスト（外部サービス不要・CI で常時実行）。"""
from __future__ import annotations

import json
from pathlib import Path

from quote_eval.dify_client import coerce_fields
from quote_eval.metrics import aggregate, score_sample
from quote_eval.normalize import norm_compact, norm_date, norm_number

DATASET = Path(__file__).resolve().parent.parent / "dataset" / "ground_truth.json"


def test_norm_number():
    assert norm_number("¥1,848,000") == 1848000
    assert norm_number(1848000) == 1848000
    assert norm_number("１，０００") == 1000  # 全角
    assert norm_number("") is None


def test_norm_date():
    assert norm_date("2026年5月12日") == "2026-05-12"
    assert norm_date("2026/04/18") == "2026-04-18"
    assert norm_date("令和8年3月31日") == "2026-03-31"
    assert norm_date("2026-06-01") == "2026-06-01"
    assert norm_date("不明") is None


def test_norm_compact():
    assert norm_compact("山田商事株式会社 御中") == "山田商事株式会社"
    assert norm_compact(" 株式会社 テック ") == "株式会社テック"


def _gold(file: str) -> dict:
    data = json.loads(DATASET.read_text(encoding="utf-8"))
    return next(s["expected"] for s in data["samples"] if s["file"] == file)


def test_perfect_prediction_scores_one():
    exp = _gold("quotation_1_techwave.pdf")
    sr = score_sample("quotation_1_techwave.pdf", exp, dict(exp))
    assert sr.field_exact_rate() == 1.0
    assert sr.line_items_score == 1.0


def test_partial_prediction():
    exp = _gold("quotation_2_officesupport.pdf")
    pred = dict(exp)
    pred["total"] = 999999          # 数値ミス
    pred["customer"] = "別会社"      # テキストミス
    sr = score_sample("quotation_2_officesupport.pdf", exp, pred)
    names_wrong = {f.name for f in sr.fields if not f.exact}
    assert names_wrong == {"total", "customer"}
    # customer はテキスト項目なので judge 対象になる
    assert any(f.name == "customer" and f.judge_eligible for f in sr.fields)


def test_date_format_tolerance():
    exp = _gold("quotation_3_mirai_kensetsu.pdf")
    pred = dict(exp)
    pred["issue_date"] = "令和8年3月31日"  # 表記違いでも正規化で一致
    sr = score_sample("quotation_3_mirai_kensetsu.pdf", exp, pred)
    assert all(f.exact for f in sr.fields if f.name == "issue_date")


def test_aggregate_runs():
    exp = _gold("quotation_1_techwave.pdf")
    sr = score_sample("quotation_1_techwave.pdf", exp, dict(exp))
    agg = aggregate([sr])
    assert agg["overall"] == 1.0
    assert agg["n"] == 1


def test_coerce_fields_unwraps_json_string():
    out = {"result": json.dumps({"quote_no": "X", "customer": "C", "vendor": "V", "total": 1})}
    assert coerce_fields(out)["quote_no"] == "X"
    direct = {"quote_no": "X", "customer": "C", "vendor": "V", "total": 1}
    assert coerce_fields(direct)["customer"] == "C"
