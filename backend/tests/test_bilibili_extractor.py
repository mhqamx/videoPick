from app.extractors.bilibili import BilibiliExtractor


class TestExtractUrl:
    def setup_method(self):
        self.ext = BilibiliExtractor()

    def test_extract_url_from_share_text(self):
        text = "【那些被发型封印的颜值！！-哔哩哔哩】 https://b23.tv/hkDTFMp"
        assert self.ext.extract_url(text) == "https://b23.tv/hkDTFMp"

    def test_extract_short_url_strip_trailing_punctuation(self):
        text = "快看这个 https://b23.tv/AbCdEFg。"
        assert self.ext.extract_url(text) == "https://b23.tv/AbCdEFg"

    def test_extract_long_bv_url(self):
        url = "https://www.bilibili.com/video/BV1xx411c7mD"
        assert self.ext.extract_url(url) == url

    def test_extract_long_av_url(self):
        url = "https://www.bilibili.com/video/av170001"
        assert self.ext.extract_url(url) == url

    def test_non_bilibili_url_not_claimed(self):
        assert self.ext.extract_url("https://v.douyin.com/oSWhN1HCRAM/") is None


class TestCanHandleSource:
    def setup_method(self):
        self.ext = BilibiliExtractor()

    def test_can_handle_bilivideo(self):
        assert self.ext.can_handle_source("https://upos-sz-mirrorcos.bilivideo.com/upgcxcode/xx.mp4")

    def test_can_handle_bilibili_host(self):
        assert self.ext.can_handle_source("https://cn-hncd-bcache-01.bilivideo.cn/upgcxcode/xx.mp4")

    def test_can_handle_upos_host(self):
        assert self.ext.can_handle_source("https://upos-hz-mirrorakam.akamaized.net/upgcxcode/xx.mp4")

    def test_unrelated_host_not_handled(self):
        assert not self.ext.can_handle_source("https://example.com/video.mp4")


class TestParseHelpers:
    def setup_method(self):
        self.ext = BilibiliExtractor()

    def test_extract_video_id_from_url(self):
        assert (
            self.ext._extract_video_id_from_url("https://www.bilibili.com/video/BV1xx411c7mD?p=1")
            == "BV1xx411c7mD"
        )
        assert self.ext._extract_video_id_from_url("https://www.bilibili.com/video/av170001") == "av170001"

    def test_canonicalize_long_video_url(self):
        class DummyClient:
            pass

        url = "https://www.bilibili.com/video/BV1xx411c7mD?p=1&share_source=copy"
        canonical = self.ext._resolve_canonical_webpage_url(DummyClient(), url)
        assert canonical == "https://www.bilibili.com/video/BV1xx411c7mD"

    def test_extract_title_from_initial_state(self):
        html = """
        <script>
        window.__INITIAL_STATE__ = {"videoData": {"title": "测试标题"}};
        </script>
        """
        assert self.ext._extract_title_from_initial_state(html) == "测试标题"

    def test_extract_progressive_candidates_from_durl(self):
        html = """
        <script>
        window.__playinfo__ = {
          "code": 0,
          "data": {
            "durl": [
              {"url": "https://upos-sz-mirrorcos.bilivideo.com/upgcxcode/main.mp4"},
              {"url": "https://upos-sz-mirrorcos.bilivideo.com/upgcxcode/backup.mp4"}
            ]
          }
        };
        </script>
        """
        candidates = self.ext._extract_progressive_candidates(html)
        assert len(candidates) == 2
        assert candidates[0].endswith("main.mp4")

    def test_extract_progressive_candidates_empty_when_dash_only(self):
        html = """
        <script>
        window.__playinfo__ = {
          "code": 0,
          "data": {
            "dash": {
              "video": [{"baseUrl": "https://upos-sz-mirrorcos.bilivideo.com/v.m4s"}],
              "audio": [{"baseUrl": "https://upos-sz-mirrorcos.bilivideo.com/a.m4s"}]
            }
          }
        };
        </script>
        """
        assert self.ext._extract_progressive_candidates(html) == []


class TestRegistryIntegration:
    def test_bilibili_extractor_registered(self):
        from app.extractors.registry import ExtractorRegistry

        registry = ExtractorRegistry()
        platforms = [e.platform for e in registry.extractors]
        assert "bilibili" in platforms
