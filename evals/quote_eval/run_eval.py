"""見積書抽出フローの評価ランナー。

  uv run python -m quote_eval.run_eval [--no-langfuse] [--no-judge] [--samples KEYWORD]

流れ: 各PDF → Dify抽出 → フィールド一致採点 → 不一致テキストはLLM-judge補助 → 集計 → Langfuse記録。
全体スコアが PASS_THRESHOLD 未満なら終了コード1（CI用）。
"""
from __future__ import annotations

import argparse
import json
import sys
from datetime import datetime, timezone

from .config import Config
from .dify_client import DifyClient, coerce_fields
from .judge import Judge
from .langfuse_logger import LangfuseLogger
from .metrics import aggregate, score_sample


def _load_dataset(cfg: Config) -> list[dict]:
    data = json.loads(cfg.dataset_path.read_text(encoding="utf-8"))
    return data["samples"]


def run(no_langfuse: bool = False, no_judge: bool = False, samples_kw: str | None = None) -> int:
    cfg = Config()
    if not cfg.dify_base or not cfg.dify_key:
        print("ERROR: DIFY_API_BASE / DIFY_API_KEY が未設定です（evals/.env を確認）。")
        return 2

    run_name = datetime.now(timezone.utc).strftime("run-%Y%m%d-%H%M%S")
    dify = DifyClient(cfg.dify_base, cfg.dify_key, cfg.dify_file_var, cfg.dify_verify_ssl)
    judge = None if no_judge else Judge(cfg)
    lf = None if no_langfuse else LangfuseLogger(cfg)

    samples = _load_dataset(cfg)
    if samples_kw:
        samples = [s for s in samples if samples_kw in s["file"]]

    results = []
    detail = []
    for s in samples:
        fname = s["file"]
        pdf = cfg.pdf_dir / fname
        print(f"\n▶ {fname}")
        try:
            outputs = dify.extract(pdf, user=run_name)
            predicted = coerce_fields(outputs)
        except Exception as e:
            print(f"  抽出失敗: {e}")
            from .metrics import SampleResult

            results.append(SampleResult(file=fname, error=str(e)))
            continue

        sr = score_sample(fname, s["expected"], predicted)

        # LLM-judge: 決定的不一致のテキスト項目を意味同値で救済
        judged = []
        if judge and cfg.judge_enabled:
            for f in sr.fields:
                if f.judge_eligible and judge.equivalent(f.name, f.expected, f.predicted):
                    f.exact = True
                    judged.append(f.name)

        results.append(sr)
        scalar = sr.field_exact_rate()
        sample_score = (scalar + sr.line_items_score) / 2
        print(
            f"  スカラ正解率={scalar:.2f} 明細={sr.line_items_score:.2f} "
            f"サンプルスコア={sample_score:.2f}"
            + (f" (judge救済: {', '.join(judged)})" if judged else "")
        )
        for f in sr.fields:
            if not f.exact:
                print(f"    ✗ {f.name}: 期待={f.expected!r} 予測={f.predicted!r}")

        if lf and lf.enabled:
            lf.log_sample(
                fname, s["expected"], predicted,
                {"field_accuracy": scalar, "line_items": sr.line_items_score,
                 "sample_score": sample_score},
                run_name,
            )
        detail.append({"file": fname, "scalar": scalar, "line_items": sr.line_items_score,
                       "sample_score": sample_score, "predicted": predicted})

    agg = aggregate(results)
    print("\n==== 集計 ====")
    print(f"サンプル数: {agg['n']}  全体スコア: {agg['overall']:.3f}  しきい値: {cfg.pass_threshold}")
    print("フィールド別正解率:")
    for k, v in agg["field_accuracy"].items():
        print(f"  {k:12} {v:.2f}")

    cfg.results_dir.mkdir(exist_ok=True)
    out = cfg.results_dir / "latest.json"
    out.write_text(json.dumps(
        {"run": run_name, "aggregate": agg, "detail": detail},
        ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"\n結果: {out}")

    if lf and lf.enabled:
        lf.flush()
        print(f"Langfuse に記録しました（run={run_name}）")

    return 0 if agg["overall"] >= cfg.pass_threshold else 1


def main():
    ap = argparse.ArgumentParser(description="見積書抽出フローの評価ランナー")
    ap.add_argument("--no-langfuse", action="store_true", help="Langfuse 記録を無効化")
    ap.add_argument("--no-judge", action="store_true", help="LLM-judge を無効化")
    ap.add_argument("--samples", help="ファイル名に含む語でフィルタ")
    args = ap.parse_args()
    sys.exit(run(args.no_langfuse, args.no_judge, args.samples))


if __name__ == "__main__":
    main()
