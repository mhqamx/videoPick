import pytest

from app.extractors.kuaishou import KuaishouExtractor


class TestExtractUrl:
    """从分享文案中提取快手 URL。"""

    def setup_method(self):
        self.ext = KuaishouExtractor()

    def test_short_url_from_share_text(self):
        text = "https://v.kuaishou.com/71hf92tY @吴希诺诺 发了一个快手作品，一起来看！"
        assert self.ext.extract_url(text) == "https://v.kuaishou.com/71hf92tY"

    def test_short_url_with_trailing_slash(self):
        assert self.ext.extract_url("https://v.kuaishou.com/AbCd1234/") == "https://v.kuaishou.com/AbCd1234/"

    def test_short_url_strip_trailing_punctuation(self):
        text = "快来看 https://v.kuaishou.com/AbCd。"
        assert self.ext.extract_url(text) == "https://v.kuaishou.com/AbCd"

    def test_long_url_short_video(self):
        url = "https://www.kuaishou.com/short-video/3xmjx5b9"
        assert self.ext.extract_url(url) == url

    def test_long_url_video(self):
        url = "https://www.kuaishou.com/video/3xmjx5b9"
        assert self.ext.extract_url(url) == url

    def test_mobile_long_url(self):
        url = "https://m.kuaishou.com/short-video/abc123"
        assert self.ext.extract_url(url) == url

    def test_no_url_returns_none(self):
        assert self.ext.extract_url("没有链接的纯文本") is None

    def test_douyin_url_not_claimed(self):
        assert self.ext.extract_url("https://v.douyin.com/oSWhN1HCRAM/ 分享") is None

    def test_arbitrary_url_not_claimed(self):
        assert self.ext.extract_url("https://example.com/video.mp4") is None


class TestCanHandleSource:
    """CDN URL 识别。"""

    def setup_method(self):
        self.ext = KuaishouExtractor()

    def test_kwimgs_cdn(self):
        assert self.ext.can_handle_source("https://txmov2.a.kwimgs.com/upic/2024/test.mp4")

    def test_ali_kwimgs_cdn(self):
        assert self.ext.can_handle_source("https://ali2.a.kwimgs.com/upic/2024/test.mp4")

    def test_kwai_net_cdn(self):
        assert self.ext.can_handle_source("https://v1.kwai.net/bs2/upload-ylab-video/abc.mp4")

    def test_kuaishou_com_cdn(self):
        assert self.ext.can_handle_source("https://video.kuaishou.com/xxx/video.mp4")

    def test_douyin_cdn_not_handled(self):
        assert not self.ext.can_handle_source("https://v26-web.douyinvod.com/video.mp4")

    def test_unrelated_cdn_not_handled(self):
        assert not self.ext.can_handle_source("https://example.com/video.mp4")


class TestExtractVideoIdFromUrl:
    """从重定向后的 URL 提取 video ID。"""

    def setup_method(self):
        self.ext = KuaishouExtractor()

    def test_short_video_path(self):
        assert self.ext._extract_video_id_from_url(
            "https://www.kuaishou.com/short-video/3xmjx5b9"
        ) == "3xmjx5b9"

    def test_video_path(self):
        assert self.ext._extract_video_id_from_url(
            "https://www.kuaishou.com/video/3xmjx5b9"
        ) == "3xmjx5b9"

    def test_no_match(self):
        assert self.ext._extract_video_id_from_url("https://www.kuaishou.com/profile/uid") is None


class TestParseApolloState:
    """解析 window.__APOLLO_STATE__ JSON。"""

    def setup_method(self):
        self.ext = KuaishouExtractor()

    def test_extract_video_url_and_caption(self):
        html = """
        <script>
        window.__APOLLO_STATE__ = {
            "VisionVideoDetailPhoto:3xmjx5b9": {
                "photoId": "3xmjx5b9",
                "caption": "测试视频标题",
                "videoUrl": "https://txmov2.a.kwimgs.com/upic/2024/test.mp4"
            }
        };
        </script>
        """
        title, candidates = self.ext._parse_apollo_state(html)
        assert title == "测试视频标题"
        assert "https://txmov2.a.kwimgs.com/upic/2024/test.mp4" in candidates

    def test_multiple_entries_deduped(self):
        html = """
        <script>
        window.__APOLLO_STATE__ = {
            "Photo:a": {"videoUrl": "https://a.kwimgs.com/1.mp4", "caption": "a"},
            "Photo:b": {"videoUrl": "https://a.kwimgs.com/1.mp4", "caption": "b"}
        };
        </script>
        """
        _, candidates = self.ext._parse_apollo_state(html)
        assert len(candidates) == 1

    def test_no_apollo_state(self):
        title, candidates = self.ext._parse_apollo_state("<html>nothing</html>")
        assert title is None
        assert candidates == []

    def test_invalid_json(self):
        html = "<script>window.__APOLLO_STATE__ = {invalid json};</script>"
        title, candidates = self.ext._parse_apollo_state(html)
        assert candidates == []


class TestParseInitialState:
    """解析 window.__INITIAL_STATE__ JSON。"""

    def setup_method(self):
        self.ext = KuaishouExtractor()

    def test_nested_video_url(self):
        html = """
        <script>
        window.__INITIAL_STATE__ = {
            "detail": {
                "work": {
                    "caption": "初始状态测试",
                    "videoUrl": "https://ali2.a.kwimgs.com/init.mp4"
                }
            }
        };
        </script>
        """
        title, candidates = self.ext._parse_initial_state(html)
        assert "https://ali2.a.kwimgs.com/init.mp4" in candidates
        assert title == "初始状态测试"

    def test_handles_undefined_values(self):
        html = """
        <script>
        window.__INITIAL_STATE__ = {"a": undefined, "b": {"videoUrl": "https://a.kwimgs.com/v.mp4"}};
        </script>
        """
        _, candidates = self.ext._parse_initial_state(html)
        assert "https://a.kwimgs.com/v.mp4" in candidates


class TestParseRawHtml:
    """原始 HTML 正则兜底解析。"""

    def setup_method(self):
        self.ext = KuaishouExtractor()

    def test_kwimgs_url(self):
        html = 'src="https://ali2.a.kwimgs.com/upic/video.mp4?tag=foo"'
        candidates = self.ext._parse_raw_html(html)
        assert any("kwimgs.com" in c for c in candidates)

    def test_escaped_url(self):
        html = r'"videoUrl":"https:\/\/txmov2.a.kwimgs.com\/upic\/test.mp4"'
        candidates = self.ext._parse_raw_html(html)
        assert any("txmov2.a.kwimgs.com" in c for c in candidates)

    def test_kwai_net_url(self):
        html = '"url": "https://v1.kwai.net/upload/video.mp4"'
        candidates = self.ext._parse_raw_html(html)
        assert any("kwai.net" in c for c in candidates)

    def test_no_match(self):
        assert self.ext._parse_raw_html("<html>no video</html>") == []


class TestRegistryIntegration:
    """确认 KuaishouExtractor 已注册到 registry。"""

    def test_kuaishou_extractor_registered(self):
        from app.extractors.registry import ExtractorRegistry
        registry = ExtractorRegistry()
        platforms = [e.platform for e in registry.extractors]
        assert "kuaishou" in platforms
        assert "douyin" in platforms

    def test_douyin_extractor_does_not_claim_kuaishou_url(self):
        from app.extractors.douyin import DouyinExtractor
        ext = DouyinExtractor()
        assert ext.extract_url("https://v.kuaishou.com/71hf92tY 快手作品") is None
