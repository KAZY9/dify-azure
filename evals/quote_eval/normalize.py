"""値の正規化（比較のための前処理）。"""
from __future__ import annotations

import re
import unicodedata

_WAREKI = {"令和": 2018, "平成": 1988, "昭和": 1925}


def norm_text(v) -> str:
    """全半角・空白を正規化し、敬称や囲み空白を除去した比較用文字列。"""
    if v is None:
        return ""
    s = unicodedata.normalize("NFKC", str(v))
    s = s.strip()
    # 末尾の敬称を除去（宛先の「御中」「様」など）
    s = re.sub(r"\s*(御中|様|殿)\s*$", "", s)
    # 連続空白を1つに
    s = re.sub(r"\s+", " ", s)
    return s


def norm_compact(v) -> str:
    """空白を全除去した厳密比較用（会社名の表記ゆれ吸収）。"""
    return re.sub(r"\s+", "", norm_text(v))


def norm_number(v):
    """'¥1,848,000' / '1848000' / 1848000 → int。失敗時 None。"""
    if v is None or v == "":
        return None
    if isinstance(v, (int, float)):
        return int(v)
    s = unicodedata.normalize("NFKC", str(v))
    m = re.findall(r"-?\d+", s.replace(",", ""))
    if not m:
        return None
    return int("".join(m)) if len(m) == 1 else int(m[0])


def norm_date(v) -> str | None:
    """各種表記を YYYY-MM-DD に正規化。失敗時 None。

    対応: 2026-06-01 / 2026/04/18 / 2026年5月12日 / 令和8年3月31日
    """
    if v is None or v == "":
        return None
    s = unicodedata.normalize("NFKC", str(v)).strip()

    # 和暦（令和/平成/昭和）
    m = re.search(r"(令和|平成|昭和)\s*(\d+)\s*年\s*(\d+)\s*月\s*(\d+)\s*日", s)
    if m:
        y = _WAREKI[m.group(1)] + int(m.group(2))
        return f"{y:04d}-{int(m.group(3)):02d}-{int(m.group(4)):02d}"

    # 西暦 年月日
    m = re.search(r"(\d{4})\s*年\s*(\d{1,2})\s*月\s*(\d{1,2})\s*日", s)
    if m:
        return f"{int(m.group(1)):04d}-{int(m.group(2)):02d}-{int(m.group(3)):02d}"

    # 区切り（- / .）
    m = re.search(r"(\d{4})[\-/\.](\d{1,2})[\-/\.](\d{1,2})", s)
    if m:
        return f"{int(m.group(1)):04d}-{int(m.group(2)):02d}-{int(m.group(3)):02d}"

    return None
