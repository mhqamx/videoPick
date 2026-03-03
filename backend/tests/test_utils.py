import pytest

from app.utils import extract_url


def test_extract_url_from_share_text() -> None:
    text = "看春晚，玩AI！https://v.douyin.com/oSWhN1HCRAM/ 复制此链接"
    assert extract_url(text) == "https://v.douyin.com/oSWhN1HCRAM/"


def test_extract_url_invalid() -> None:
    with pytest.raises(ValueError):
        extract_url("no url here")
