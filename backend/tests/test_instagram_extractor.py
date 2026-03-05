from pathlib import Path

from app.extractors.instagram import InstagramExtractor


class TestExtractUrl:
    def setup_method(self):
        self.ext = InstagramExtractor()

    def test_extract_reel_url_from_text(self):
        text = "分享一个视频 https://www.instagram.com/reel/DVXmWNtk1GC/?igsh=abc123"
        assert self.ext.extract_url(text) == "https://www.instagram.com/reel/DVXmWNtk1GC/?igsh=abc123"

    def test_extract_post_url(self):
        url = "https://www.instagram.com/p/C7AbCdEf123/"
        assert self.ext.extract_url(url) == url

    def test_extract_tv_url(self):
        url = "https://www.instagram.com/tv/C7AbCdEf123/"
        assert self.ext.extract_url(url) == url

    def test_strip_trailing_punctuation(self):
        text = "看这个 https://www.instagram.com/reel/DVXmWNtk1GC/。"
        assert self.ext.extract_url(text) == "https://www.instagram.com/reel/DVXmWNtk1GC/"

    def test_non_instagram_url_not_claimed(self):
        assert self.ext.extract_url("https://vm.tiktok.com/ZP8QJ3cWW/") is None


class TestCookieParsing:
    def setup_method(self):
        self.ext = InstagramExtractor()

    def test_parse_netscape_cookie_file(self, tmp_path: Path):
        cookie_file = tmp_path / "instagram_cookies.txt"
        cookie_file.write_text(
            """# Netscape HTTP Cookie File
#HttpOnly_.instagram.com\tTRUE\t/\tTRUE\t2147483647\tsessionid\tsession_value
.instagram.com\tTRUE\t/\tFALSE\t2147483647\tcsrftoken\tcsrf_value
""",
            encoding="utf-8",
        )

        parsed = self.ext._parse_cookie_file(cookie_file)
        assert parsed["sessionid"] == "session_value"
        assert parsed["csrftoken"] == "csrf_value"

    def test_parse_cookie_header_style(self, tmp_path: Path):
        cookie_file = tmp_path / "cookie_header.txt"
        cookie_file.write_text("sessionid=s1; csrftoken=c1; ds_user_id=10001", encoding="utf-8")
        parsed = self.ext._parse_cookie_file(cookie_file)
        assert parsed["sessionid"] == "s1"
        assert parsed["csrftoken"] == "c1"
        assert parsed["ds_user_id"] == "10001"


class TestParseHelpers:
    def setup_method(self):
        self.ext = InstagramExtractor()

    def test_extract_shortcode_from_url(self):
        assert self.ext._extract_shortcode_from_url("https://www.instagram.com/reel/DVXmWNtk1GC/") == "DVXmWNtk1GC"
        assert self.ext._extract_shortcode_from_url("https://www.instagram.com/p/ABC123xyz/") == "ABC123xyz"

    def test_normalize_input_url_removes_query(self):
        raw = "https://www.instagram.com/reel/DVXmWNtk1GC/?igsh=abc&foo=bar"
        assert self.ext._normalize_input_url(raw) == "https://www.instagram.com/reel/DVXmWNtk1GC/"

    def test_append_query(self):
        url = "https://www.instagram.com/reel/DVXmWNtk1GC/?foo=bar"
        appended = self.ext._append_query(url, {"__a": "1", "__d": "dis"})
        assert "__a=1" in appended
        assert "__d=dis" in appended
        assert "foo=bar" in appended


class TestParseHtml:
    def setup_method(self):
        self.ext = InstagramExtractor()

    def test_parse_ld_json_video_object(self):
        html = """
        <script type="application/ld+json">
        {
          "@context": "https://schema.org",
          "@type": "VideoObject",
          "name": "Instagram Reel 标题",
          "contentUrl": "https://scontent.cdninstagram.com/v/t50.2886-16/abcd.mp4"
        }
        </script>
        """
        title, candidates = self.ext._parse_html(html)
        assert title == "Instagram Reel 标题"
        assert len(candidates) == 1
        assert "cdninstagram.com" in candidates[0]

    def test_parse_video_url_from_html_fallback(self):
        html = r'"video_url":"https:\/\/instagram.fsha1-1.fna.fbcdn.net\/v\/t50.2886-16\/xyz.mp4?stp=dst"'
        title, candidates = self.ext._parse_html(html)
        assert title is None
        assert len(candidates) == 1
        assert "fbcdn.net" in candidates[0]

    def test_collect_from_json(self):
        payload = {
            "graphql": {
                "shortcode_media": {
                    "title": "标题A",
                    "video_url": "https://scontent.cdninstagram.com/v/t50.2886-16/test.mp4",
                }
            }
        }
        title, candidates = self.ext._collect_from_json(payload)
        assert title == "标题A"
        assert candidates[0].endswith("test.mp4")

    def test_extract_from_media_info_payload(self):
        payload = {
            "items": [
                {
                    "id": "3843709459303190914_54675136281",
                    "code": "DVXmWNtk1GC",
                    "media_type": 2,
                    "caption": {"text": "来自 media info 的标题"},
                    "video_versions": [
                        {
                            "url": "https://scontent-nrt1-2.cdninstagram.com/v/t50.2886-16/abcdef.mp4"
                        }
                    ],
                }
            ]
        }
        title, video_id, candidates, image_urls, webpage_url = self.ext._extract_from_media_info_payload(payload)
        assert title == "来自 media info 的标题"
        assert video_id == "3843709459303190914_54675136281"
        assert candidates[0].endswith("abcdef.mp4")
        assert image_urls == []
        assert webpage_url == "https://www.instagram.com/reel/DVXmWNtk1GC/"

    def test_extract_from_media_info_payload_image_carousel(self):
        payload = {
            "items": [
                {
                    "id": "3837213674872331406_74350098078",
                    "code": "DVAhYHCCVyO",
                    "media_type": 8,
                    "caption": {"text": "图文帖子"},
                    "image_versions2": {
                        "candidates": [
                            {"url": "https://scontent-nrt6-1.cdninstagram.com/v/t51.82787-15/cover_s150.heic", "width": 150, "height": 150},
                            {"url": "https://scontent-nrt6-1.cdninstagram.com/v/t51.82787-15/cover_s480.heic", "width": 480, "height": 480},
                        ]
                    },
                    "carousel_media": [
                        {
                            "media_type": 1,
                            "image_versions2": {
                                "candidates": [
                                    {"url": "https://scontent-nrt6-1.cdninstagram.com/v/t51.82787-15/1_s150.heic", "width": 150, "height": 150},
                                    {"url": "https://scontent-nrt6-1.cdninstagram.com/v/t51.82787-15/1_s720.heic", "width": 720, "height": 720},
                                ]
                            },
                        },
                        {
                            "media_type": 1,
                            "image_versions2": {
                                "candidates": [
                                    {"url": "https://scontent-nrt6-1.cdninstagram.com/v/t51.82787-15/2_s150.heic", "width": 150, "height": 150},
                                    {"url": "https://scontent-nrt6-1.cdninstagram.com/v/t51.82787-15/2_s720.heic", "width": 720, "height": 720},
                                ]
                            },
                        },
                        {
                            "media_type": 1,
                            "image_versions2": {
                                "candidates": [
                                    {"url": "https://scontent-nrt6-1.cdninstagram.com/v/t51.82787-15/3_s150.heic", "width": 150, "height": 150},
                                    {"url": "https://scontent-nrt6-1.cdninstagram.com/v/t51.82787-15/3_s720.heic", "width": 720, "height": 720},
                                ]
                            },
                        },
                    ],
                }
            ]
        }
        title, video_id, candidates, image_urls, webpage_url = self.ext._extract_from_media_info_payload(payload)
        assert title == "图文帖子"
        assert video_id == "3837213674872331406_74350098078"
        assert candidates == []
        assert len(image_urls) == 3
        assert image_urls[0].endswith("1_s720.heic")
        assert webpage_url == "https://www.instagram.com/p/DVAhYHCCVyO/"


class TestRegistryIntegration:
    def test_instagram_extractor_registered(self):
        from app.extractors.registry import ExtractorRegistry

        registry = ExtractorRegistry()
        platforms = [e.platform for e in registry.extractors]
        assert "instagram" in platforms
