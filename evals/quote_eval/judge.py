"""LLM-as-judge（Azure OpenAI / gpt-4.1）。決定的比較で不一致のテキスト項目を意味同値で再判定。"""
from __future__ import annotations

from .config import Config


class Judge:
    def __init__(self, cfg: Config):
        self.cfg = cfg
        self._client = None

    def _client_lazy(self):
        if self._client is None:
            from openai import AzureOpenAI

            self._client = AzureOpenAI(
                api_key=self.cfg.azure_key,
                azure_endpoint=self.cfg.azure_endpoint,
                api_version=self.cfg.azure_api_version,
            )
        return self._client

    def equivalent(self, field_name: str, expected, predicted) -> bool:
        """expected と predicted が同じ意味の値か判定（yes/no）。"""
        if not self.cfg.judge_enabled:
            return False
        prompt = (
            "あなたは見積書の項目抽出の採点者です。\n"
            f"項目: {field_name}\n"
            f"正解: {expected!r}\n"
            f"予測: {predicted!r}\n"
            "両者が実質的に同じ値を指すなら yes、異なるなら no とだけ答えてください。"
            "表記ゆれ（株式会社の有無・スペース・全半角・敬称）は同じと見なします。"
        )
        try:
            resp = self._client_lazy().chat.completions.create(
                model=self.cfg.azure_deployment,
                messages=[{"role": "user", "content": prompt}],
                max_tokens=3,
                temperature=0,
            )
            ans = (resp.choices[0].message.content or "").strip().lower()
            return ans.startswith("y")
        except Exception:
            return False
