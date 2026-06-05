"""Dify ワークフローアプリ API クライアント（ファイルアップロード → 実行）。"""
from __future__ import annotations

import json
from pathlib import Path

import requests


class DifyClient:
    def __init__(self, base: str, api_key: str, file_var: str = "file", verify_ssl: bool = False):
        self.base = base.rstrip("/")
        self.headers = {"Authorization": f"Bearer {api_key}"}
        self.file_var = file_var
        self.verify = verify_ssl

    def upload_file(self, path: Path, user: str = "eval") -> str:
        """ファイルをアップロードし upload_file_id を返す。"""
        with open(path, "rb") as fh:
            files = {"file": (path.name, fh, "application/pdf")}
            data = {"user": user}
            r = requests.post(
                f"{self.base}/files/upload",
                headers=self.headers,
                files=files,
                data=data,
                verify=self.verify,
                timeout=60,
            )
        r.raise_for_status()
        return r.json()["id"]

    def run_workflow(self, upload_file_id: str, user: str = "eval") -> dict:
        """ワークフローを blocking 実行し outputs(dict) を返す。"""
        payload = {
            "inputs": {
                self.file_var: {
                    "transfer_method": "local_file",
                    "upload_file_id": upload_file_id,
                    "type": "document",
                }
            },
            "response_mode": "blocking",
            "user": user,
        }
        r = requests.post(
            f"{self.base}/workflows/run",
            headers={**self.headers, "Content-Type": "application/json"},
            data=json.dumps(payload),
            verify=self.verify,
            timeout=180,
        )
        r.raise_for_status()
        body = r.json()
        return (body.get("data") or {}).get("outputs") or {}

    def extract(self, path: Path, user: str = "eval") -> dict:
        fid = self.upload_file(path, user)
        return self.run_workflow(fid, user)


def coerce_fields(outputs: dict) -> dict:
    """ワークフロー出力を抽出フィールドの dict に正規化する。

    - End ノードが各項目を直接出力 → そのまま使う
    - 単一オブジェクト/JSON文字列(result, output, text 等)で出力 → 展開
    """
    if not isinstance(outputs, dict):
        return {}
    target_keys = {"quote_no", "customer", "vendor", "total"}
    if target_keys & set(outputs.keys()):
        return outputs
    # 単一キーに JSON 文字列 or dict が入っているケース
    for key in ("result", "output", "data", "text", "json"):
        if key in outputs:
            val = outputs[key]
            if isinstance(val, dict):
                return val
            if isinstance(val, str):
                try:
                    parsed = json.loads(val)
                    if isinstance(parsed, dict):
                        return parsed
                except json.JSONDecodeError:
                    pass
    # 値が1つだけの dict なら、その中身を試す
    if len(outputs) == 1:
        only = next(iter(outputs.values()))
        if isinstance(only, dict):
            return only
    return outputs
