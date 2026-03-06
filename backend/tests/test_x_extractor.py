from pathlib import Path

from app.extractors.x import XExtractor


class TestExtractUrl:
    def setup_method(self):
        self.ext = XExtractor()

    def test_extract_x_status_url(self):
        text = "https://x.com/SSSQ58/status/2028415517846012266?s=20"
        assert self.ext.extract_url(text) == text

    def test_extract_twitter_status_url(self):
        text = "看看这个 https://twitter.com/SSSQ58/status/2028415517846012266?t=xx"
        assert self.ext.extract_url(text) == "https://twitter.com/SSSQ58/status/2028415517846012266?t=xx"

    def test_strip_trailing_punctuation(self):
        text = "https://x.com/SSSQ58/status/2028415517846012266?s=20。"
        assert self.ext.extract_url(text) == "https://x.com/SSSQ58/status/2028415517846012266?s=20"

    def test_non_x_url_not_claimed(self):
        assert self.ext.extract_url("https://www.instagram.com/reel/DVXmWNtk1GC/") is None


class TestCookieParsing:
    def setup_method(self):
        self.ext = XExtractor()

    def test_parse_netscape_cookie_file(self, tmp_path: Path):
        cookie_file = tmp_path / "x_cookies.txt"
        cookie_file.write_text(
            """# Netscape HTTP Cookie File
#HttpOnly_.x.com\tTRUE\t/\tTRUE\t2147483647\tauth_token\tauth_value
.x.com\tTRUE\t/\tFALSE\t2147483647\tct0\tct0_value
""",
            encoding="utf-8",
        )
        parsed = self.ext._parse_cookie_file(cookie_file)
        assert parsed["auth_token"] == "auth_value"
        assert parsed["ct0"] == "ct0_value"

    def test_parse_cookie_header_style(self, tmp_path: Path):
        cookie_file = tmp_path / "cookie_header.txt"
        cookie_file.write_text("auth_token=a1; ct0=c1; guest_id=v1", encoding="utf-8")
        parsed = self.ext._parse_cookie_file(cookie_file)
        assert parsed["auth_token"] == "a1"
        assert parsed["ct0"] == "c1"
        assert parsed["guest_id"] == "v1"


class TestParseHelpers:
    def setup_method(self):
        self.ext = XExtractor()

    def test_extract_tweet_id(self):
        assert self.ext._extract_tweet_id("https://x.com/SSSQ58/status/2028415517846012266?s=20") == "2028415517846012266"
        assert self.ext._extract_tweet_id("https://x.com/home") is None

    def test_extract_main_js_url(self):
        html = '<script src="https://abs.twimg.com/responsive-web/client-web/main.1c95ab1a.js"></script>'
        assert self.ext._extract_main_js_url(html) == "https://abs.twimg.com/responsive-web/client-web/main.1c95ab1a.js"

    def test_extract_query_id(self):
        js = '...queryId:"oSBAzPwnB3u5R9KqxACO3Q",operationName:"TweetResultByRestId"...'
        assert self.ext._extract_query_id(js) == "oSBAzPwnB3u5R9KqxACO3Q"

    def test_extract_bearer_token(self):
        token = "AAAAAAAAAAAAAAAAAAAAANRILgAAAAAAnNwIzUejRCOuH5E6I8xnZz4puTs%3D1Zv7ttfk8LF81IUq16cHjhLTvJu4FA33AGWWjCpTnA"
        js = f"...{token}..."
        assert self.ext._extract_bearer_token(js) == token

    def test_extract_video_candidates_from_graphql(self):
        payload = {
            "data": {
                "tweetResult": {
                    "result": {
                        "legacy": {
                            "full_text": "测试 X 视频标题",
                            "extended_entities": {
                                "media": [
                                    {
                                        "video_info": {
                                            "variants": [
                                                {
                                                    "content_type": "application/x-mpegURL",
                                                    "url": "https://video.twimg.com/ext_tw_video/xxx/pu/pl/playlist.m3u8",
                                                },
                                                {
                                                    "bitrate": 832000,
                                                    "content_type": "video/mp4",
                                                    "url": "https://video.twimg.com/ext_tw_video/xxx/pu/vid/360x640/a.mp4",
                                                },
                                                {
                                                    "bitrate": 2176000,
                                                    "content_type": "video/mp4",
                                                    "url": "https://video.twimg.com/ext_tw_video/xxx/pu/vid/720x1280/b.mp4",
                                                },
                                            ]
                                        }
                                    }
                                ]
                            },
                        }
                    }
                }
            }
        }
        title, candidates, _images = self.ext._extract_media_from_graphql(payload)
        assert title == "测试 X 视频标题"
        assert len(candidates) == 3
        assert candidates[0].endswith("/b.mp4")

    def test_extract_video_candidates_from_unified_card_binding(self):
        payload = {
            "data": {
                "tweetResult": {
                    "result": {
                        "legacy": {
                            "full_text": "卡片视频",
                        },
                        "card": {
                            "legacy": {
                                "binding_values": [
                                    {
                                        "key": "unified_card",
                                        "value": {
                                            "string_value": "{\"media_entities\":{\"13_test\":{\"type\":\"video\",\"video_info\":{\"variants\":[{\"content_type\":\"video/mp4\",\"bitrate\":256000,\"url\":\"https://video.twimg.com/amplify_video/test/vid/480x270/a.mp4\"},{\"content_type\":\"video/mp4\",\"bitrate\":2176000,\"url\":\"https://video.twimg.com/amplify_video/test/vid/1280x720/b.mp4\"}]}}}}"
                                        },
                                    }
                                ]
                            }
                        },
                    }
                }
            }
        }
        title, candidates, _images = self.ext._extract_media_from_graphql(payload)
        assert title == "卡片视频"
        assert len(candidates) == 2
        assert candidates[0].endswith("/b.mp4")


class TestCanHandleSource:
    def setup_method(self):
        self.ext = XExtractor()

    def test_video_twimg(self):
        assert self.ext.can_handle_source("https://video.twimg.com/ext_tw_video/xxx/pu/vid/720x1280/test.mp4")

    def test_subdomain_twimg(self):
        assert self.ext.can_handle_source("https://pbs.twimg.com/media/abc.jpg")

    def test_unrelated_host_not_handled(self):
        assert not self.ext.can_handle_source("https://example.com/video.mp4")


class TestRegistryIntegration:
    def test_x_extractor_registered(self):
        from app.extractors.registry import ExtractorRegistry

        registry = ExtractorRegistry()
        platforms = [e.platform for e in registry.extractors]
        assert "x" in platforms
