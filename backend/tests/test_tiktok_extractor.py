from app.extractors.tiktok import TikTokExtractor


class TestExtractUrl:
    """从分享文案中提取 TikTok URL。"""

    def setup_method(self):
        self.ext = TikTokExtractor()

    def test_vm_short_url_from_share_text(self):
        text = "看这个视频 https://vm.tiktok.com/ZP8QJ3cWW/ 超好看"
        assert self.ext.extract_url(text) == "https://vm.tiktok.com/ZP8QJ3cWW/"

    def test_vt_short_url(self):
        assert self.ext.extract_url("https://vt.tiktok.com/ZSAbCd123/") == "https://vt.tiktok.com/ZSAbCd123/"

    def test_tiktok_t_share_url(self):
        assert self.ext.extract_url("https://www.tiktok.com/t/ZT12AbCde/") == "https://www.tiktok.com/t/ZT12AbCde/"

    def test_long_video_url(self):
        url = "https://www.tiktok.com/@demo_user/video/7483029876543212345"
        assert self.ext.extract_url(url) == url

    def test_strip_trailing_punctuation(self):
        text = "快看 https://vm.tiktok.com/ZP8QJ3cWW/。"
        assert self.ext.extract_url(text) == "https://vm.tiktok.com/ZP8QJ3cWW/"

    def test_non_tiktok_url_not_claimed(self):
        assert self.ext.extract_url("https://v.douyin.com/oSWhN1HCRAM/") is None


class TestCanHandleSource:
    """TikTok CDN URL 识别。"""

    def setup_method(self):
        self.ext = TikTokExtractor()

    def test_tiktokcdn_host(self):
        assert self.ext.can_handle_source("https://v16m.tiktokcdn.com/abc/video.mp4")

    def test_tiktokv_host(self):
        assert self.ext.can_handle_source("https://api16-normal-c-useast1a.tiktokv.com/obj/tos/useast1a.mp4")

    def test_byteoversea_host(self):
        assert self.ext.can_handle_source("https://v16m-byteoversea.com/obj/tos/video.mp4")

    def test_unrelated_host_not_handled(self):
        assert not self.ext.can_handle_source("https://example.com/video.mp4")


class TestExtractVideoIdFromUrl:
    def setup_method(self):
        self.ext = TikTokExtractor()

    def test_video_path(self):
        assert (
            self.ext._extract_video_id_from_url(
                "https://www.tiktok.com/@foo/video/7483029876543212345?is_from_webapp=1"
            )
            == "7483029876543212345"
        )

    def test_v_path(self):
        assert self.ext._extract_video_id_from_url("https://www.tiktok.com/v/7483029876543212345") == "7483029876543212345"

    def test_no_match(self):
        assert self.ext._extract_video_id_from_url("https://www.tiktok.com/@foo") is None


class TestParseHtml:
    def setup_method(self):
        self.ext = TikTokExtractor()

    def test_parse_universal_data(self):
        html = """
        <script id="__UNIVERSAL_DATA_FOR_REHYDRATION__" type="application/json">
        {
          "__DEFAULT_SCOPE__": {
            "webapp.video-detail": {
              "itemInfo": {
                "itemStruct": {
                  "desc": "测试 TikTok 视频",
                  "video": {
                    "downloadAddr": "https://v16m.tiktokcdn.com/obj/tos/test_download.mp4",
                    "playAddr": "https://v16m.tiktokcdn.com/obj/tos/test_play.mp4"
                  }
                }
              }
            }
          }
        }
        </script>
        """
        title, candidates = self.ext._parse_html(html)
        assert title == "测试 TikTok 视频"
        assert len(candidates) == 2
        assert candidates[0].endswith("test_download.mp4")

    def test_parse_sigi_state_assignment(self):
        html = """
        <script>
        window['SIGI_STATE'] = {
          "ItemModule": {
            "7483": {
              "desc": "SIGI 标题",
              "video": {
                "downloadAddr": "https://api16-normal-c-useast1a.tiktokv.com/obj/tos/test.mp4"
              }
            }
          }
        };
        </script>
        """
        title, candidates = self.ext._parse_html(html)
        assert title == "SIGI 标题"
        assert any("tiktokv.com" in c for c in candidates)

    def test_parse_raw_html_fallback(self):
        html = r'"url":"https:\/\/v16m.tiktokcdn.com\/obj\/tos\/raw_fallback.mp4"'
        title, candidates = self.ext._parse_html(html)
        assert title is None
        assert any("raw_fallback.mp4" in c for c in candidates)

    def test_no_video_returns_empty(self):
        title, candidates = self.ext._parse_html("<html>no media</html>")
        assert title is None
        assert candidates == []


class TestRegistryIntegration:
    def test_tiktok_extractor_registered(self):
        from app.extractors.registry import ExtractorRegistry

        registry = ExtractorRegistry()
        platforms = [e.platform for e in registry.extractors]
        assert "tiktok" in platforms

    def test_douyin_extractor_does_not_claim_tiktok_url(self):
        from app.extractors.douyin import DouyinExtractor

        ext = DouyinExtractor()
        assert ext.extract_url("https://vm.tiktok.com/ZP8QJ3cWW/") is None
