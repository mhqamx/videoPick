from app.main import _is_allowed_source


def test_bilibili_upos_akamaized_is_allowed():
    url = "https://upos-hz-mirrorakam.akamaized.net/upgcxcode/27/68/36353936827/36353936827-1-192.mp4"
    assert _is_allowed_source(url)


def test_non_upos_akamaized_is_not_allowed():
    url = "https://example.akamaized.net/video.mp4"
    assert not _is_allowed_source(url)
