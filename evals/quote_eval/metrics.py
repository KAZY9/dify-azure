"""フィールド単位の採点ロジック（決定的）。"""
from __future__ import annotations

from dataclasses import dataclass, field

from .normalize import norm_compact, norm_date, norm_number

# フィールドの型分類
NUMERIC_FIELDS = ("subtotal", "tax", "total")
DATE_FIELDS = ("issue_date", "valid_until")
ID_FIELDS = ("quote_no",)
TEXT_FIELDS = ("customer", "vendor", "subject")  # 不一致時に LLM-judge 対象
SCALAR_FIELDS = ID_FIELDS + DATE_FIELDS + TEXT_FIELDS + NUMERIC_FIELDS


@dataclass
class FieldResult:
    name: str
    expected: object
    predicted: object
    exact: bool          # 決定的比較での一致
    judge_eligible: bool  # 不一致かつ LLM-judge で再判定し得る


@dataclass
class SampleResult:
    file: str
    fields: list[FieldResult] = field(default_factory=list)
    line_items_score: float = 0.0
    error: str | None = None

    def field_exact_rate(self) -> float:
        if not self.fields:
            return 0.0
        return sum(1 for f in self.fields if f.exact) / len(self.fields)


def _scalar_match(name: str, exp, pred) -> bool:
    if name in NUMERIC_FIELDS:
        return norm_number(exp) == norm_number(pred) and norm_number(exp) is not None
    if name in DATE_FIELDS:
        de, dp = norm_date(exp), norm_date(pred)
        return de is not None and de == dp
    # ID / TEXT は空白除去の厳密比較
    return norm_compact(exp) == norm_compact(pred) and norm_compact(exp) != ""


def score_sample(file: str, expected: dict, predicted: dict) -> SampleResult:
    """1 件分のフィールド採点（LLM-judge 前の決定的スコア）。"""
    res = SampleResult(file=file)
    for name in SCALAR_FIELDS:
        exp = expected.get(name)
        pred = (predicted or {}).get(name)
        exact = _scalar_match(name, exp, pred)
        res.fields.append(
            FieldResult(
                name=name,
                expected=exp,
                predicted=pred,
                exact=exact,
                judge_eligible=(not exact) and (name in TEXT_FIELDS),
            )
        )
    res.line_items_score = _score_line_items(
        expected.get("line_items") or [], (predicted or {}).get("line_items") or []
    )
    return res


def _score_line_items(exp_items: list, pred_items: list) -> float:
    """明細は「件数一致」と「金額合計一致」の平均で簡易採点（0〜1）。"""
    if not exp_items:
        return 1.0 if not pred_items else 0.0
    count_ok = 1.0 if len(exp_items) == len(pred_items) else 0.0
    exp_sum = sum(norm_number(i.get("amount")) or 0 for i in exp_items)
    pred_sum = sum(norm_number(i.get("amount")) or 0 for i in (pred_items or []))
    sum_ok = 1.0 if exp_sum == pred_sum and exp_sum > 0 else 0.0
    return (count_ok + sum_ok) / 2


def aggregate(results: list[SampleResult]) -> dict:
    """全サンプルの集計（フィールド別正解率・全体スコア）。"""
    per_field: dict[str, list[bool]] = {}
    overall_parts: list[float] = []
    for r in results:
        if r.error:
            overall_parts.append(0.0)
            continue
        for f in r.fields:
            per_field.setdefault(f.name, []).append(f.exact)
        # 1 件のスコア = スカラ正解率 と 明細スコア の平均
        overall_parts.append((r.field_exact_rate() + r.line_items_score) / 2)
    field_acc = {k: (sum(v) / len(v) if v else 0.0) for k, v in per_field.items()}
    overall = sum(overall_parts) / len(overall_parts) if overall_parts else 0.0
    return {"overall": overall, "field_accuracy": field_acc, "n": len(results)}
