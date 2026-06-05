"""Langfuse へのトレース/スコア記録（任意・キー未設定ならスキップ）。"""
from __future__ import annotations

from .config import Config


class LangfuseLogger:
    def __init__(self, cfg: Config):
        self.cfg = cfg
        self.lf = None
        if cfg.langfuse_enabled:
            try:
                from langfuse import Langfuse

                self.lf = Langfuse(
                    public_key=cfg.langfuse_public,
                    secret_key=cfg.langfuse_secret,
                    host=cfg.langfuse_host,
                )
            except Exception as e:  # SDK 不整合等でも評価本体は止めない
                print(f"[langfuse] 初期化失敗のためスキップ: {e}")
                self.lf = None

    @property
    def enabled(self) -> bool:
        return self.lf is not None

    def log_sample(self, file: str, expected: dict, predicted: dict, scores: dict, run_name: str):
        if not self.lf:
            return
        try:
            trace = self.lf.trace(
                name="quote-extract-eval",
                input={"file": file},
                output=predicted,
                metadata={"expected": expected, "run": run_name},
                tags=["quote-extraction", run_name],
            )
            for k, v in scores.items():
                trace.score(name=k, value=float(v))
        except Exception as e:
            print(f"[langfuse] 記録失敗: {e}")

    def flush(self):
        if self.lf:
            try:
                self.lf.flush()
            except Exception:
                pass
