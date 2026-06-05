"""環境変数の読み込み。"""
from __future__ import annotations

import os
from dataclasses import dataclass
from pathlib import Path

from dotenv import load_dotenv

EVALS_DIR = Path(__file__).resolve().parent.parent
REPO_DIR = EVALS_DIR.parent
load_dotenv(EVALS_DIR / ".env")


def _bool(v: str | None, default: bool) -> bool:
    if v is None:
        return default
    return v.strip().lower() in ("1", "true", "yes", "on")


@dataclass
class Config:
    dify_base: str = os.getenv("DIFY_API_BASE", "")
    dify_key: str = os.getenv("DIFY_API_KEY", "")
    dify_file_var: str = os.getenv("DIFY_FILE_VAR", "file")
    dify_verify_ssl: bool = _bool(os.getenv("DIFY_VERIFY_SSL"), False)

    azure_endpoint: str = os.getenv("AZURE_OPENAI_ENDPOINT", "")
    azure_key: str = os.getenv("AZURE_OPENAI_API_KEY", "")
    azure_deployment: str = os.getenv("AZURE_OPENAI_DEPLOYMENT", "gpt-4.1")
    azure_api_version: str = os.getenv("AZURE_OPENAI_API_VERSION", "2024-10-21")

    langfuse_host: str = os.getenv("LANGFUSE_HOST", "https://cloud.langfuse.com")
    langfuse_public: str = os.getenv("LANGFUSE_PUBLIC_KEY", "")
    langfuse_secret: str = os.getenv("LANGFUSE_SECRET_KEY", "")

    pass_threshold: float = float(os.getenv("PASS_THRESHOLD", "0.8"))

    dataset_path: Path = EVALS_DIR / "dataset" / "ground_truth.json"
    pdf_dir: Path = REPO_DIR / "samples" / "quotations"
    results_dir: Path = EVALS_DIR / "results"

    @property
    def langfuse_enabled(self) -> bool:
        return bool(self.langfuse_public and self.langfuse_secret)

    @property
    def judge_enabled(self) -> bool:
        return bool(self.azure_endpoint and self.azure_key)
