import pytest

from app.extractors.xiaohongshu import XiaohongshuExtractor


class TestExtractUrl:
    """从分享文案中提取小红书 URL。"""

    def setup_method(self):
        self.ext = XiaohongshuExtractor()

    def test_short_url_with_o_prefix(self):
        text = "跳给你们看 http://xhslink.com/o/2z7YRSHBEWZ 复制后打开【小红书】查看笔记！"
        assert self.ext.extract_url(text) == "http://xhslink.com/o/2z7YRSHBEWZ"

    def test_short_url_bare(self):
        assert self.ext.extract_url("http://xhslink.com/AbCd1234") == "http://xhslink.com/AbCd1234"

    def test_short_url_https(self):
        assert self.ext.extract_url("https://xhslink.com/o/AbCd1234") == "https://xhslink.com/o/AbCd1234"

    def test_short_url_with_trailing_slash(self):
        assert self.ext.extract_url("http://xhslink.com/o/AbCd/") == "http://xhslink.com/o/AbCd/"

    def test_short_url_strip_trailing_punctuation(self):
        text = "来看 http://xhslink.com/o/AbCd。"
        assert self.ext.extract_url(text) == "http://xhslink.com/o/AbCd"

    def test_long_url_explore(self):
        url = "https://www.xiaohongshu.com/explore/abc123def456"
        assert self.ext.extract_url(url) == url

    def test_long_url_discovery_item(self):
        url = "https://www.xiaohongshu.com/discovery/item/abc123def456"
        assert self.ext.extract_url(url) == url

    def test_long_url_without_www(self):
        url = "https://xiaohongshu.com/explore/abc123"
        assert self.ext.extract_url(url) == url

    def test_no_url_returns_none(self):
        assert self.ext.extract_url("没有链接的纯文本") is None

    def test_douyin_url_not_claimed(self):
        assert self.ext.extract_url("https://v.douyin.com/oSWhN1HCRAM/ 分享") is None

    def test_kuaishou_url_not_claimed(self):
        assert self.ext.extract_url("https://v.kuaishou.com/71hf92tY") is None

    def test_arbitrary_url_not_claimed(self):
        assert self.ext.extract_url("https://example.com/video.mp4") is None


class TestCanHandleSource:
    """CDN URL 识别。"""

    def setup_method(self):
        self.ext = XiaohongshuExtractor()

    def test_sns_video_bd_cdn(self):
        assert self.ext.can_handle_source("https://sns-video-bd.xhscdn.com/stream/abc/video.mp4")

    def test_sns_video_hw_cdn(self):
        assert self.ext.can_handle_source("https://sns-video-hw.xhscdn.com/stream/abc/video.mp4")

    def test_sns_video_al_cdn(self):
        assert self.ext.can_handle_source("https://sns-video-al.xhscdn.com/stream/abc/video.mp4")

    def test_generic_xhscdn_com(self):
        assert self.ext.can_handle_source("https://other.xhscdn.com/video.mp4")

    def test_xhscdn_net(self):
        assert self.ext.can_handle_source("https://sns-video-bd.xhscdn.net/stream/video.mp4")

    def test_douyin_cdn_not_handled(self):
        assert not self.ext.can_handle_source("https://v26-web.douyinvod.com/video.mp4")

    def test_kuaishou_cdn_not_handled(self):
        assert not self.ext.can_handle_source("https://txmov2.a.kwimgs.com/video.mp4")

    def test_unrelated_cdn_not_handled(self):
        assert not self.ext.can_handle_source("https://example.com/video.mp4")


class TestExtractNoteIdFromUrl:
    """从重定向后的 URL 提取 note ID。"""

    def setup_method(self):
        self.ext = XiaohongshuExtractor()

    def test_explore_path(self):
        assert self.ext._extract_note_id_from_url(
            "https://www.xiaohongshu.com/explore/abc123def456"
        ) == "abc123def456"

    def test_discovery_item_path(self):
        assert self.ext._extract_note_id_from_url(
            "https://www.xiaohongshu.com/discovery/item/abc123def456"
        ) == "abc123def456"

    def test_no_match(self):
        assert self.ext._extract_note_id_from_url("https://www.xiaohongshu.com/profile/uid") is None


class TestParseInitialState:
    """解析 window.__INITIAL_STATE__ JSON（支持两种路径）。"""

    def setup_method(self):
        self.ext = XiaohongshuExtractor()

    def test_mobile_share_page_structure(self):
        """移动端分享页: noteData.data.noteData"""
        html = """
        <script>
        window.__INITIAL_STATE__ = {
          "noteData": {
            "data": {
              "noteData": {
                "type": "video",
                "title": "移动端视频",
                "noteId": "abc123",
                "video": {
                  "media": {
                    "stream": {
                      "h264": [{"masterUrl": "https://sns-video-hs.xhscdn.com/stream/h264.mp4"}],
                      "h265": [{"masterUrl": "https://sns-video-hs.xhscdn.com/stream/h265.mp4"}]
                    }
                  }
                }
              }
            }
          }
        };
        </script>
        """
        title, candidates, media_type, image_urls = self.ext._parse_initial_state(html)
        assert title == "移动端视频"
        assert len(candidates) == 2
        assert candidates[0].endswith("h264.mp4")
        assert media_type == "video"

    def test_video_note_extracts_h264(self):
        html = """
        <script>
        window.__INITIAL_STATE__ = {
          "note": {
            "noteDetailMap": {
              "abc123": {
                "note": {
                  "type": "video",
                  "title": "测试视频标题",
                  "video": {
                    "media": {
                      "stream": {
                        "h264": [{"masterUrl": "https://sns-video-bd.xhscdn.com/stream/abc/h264.mp4"}]
                      }
                    }
                  }
                }
              }
            }
          }
        };
        </script>
        """
        title, candidates, media_type, _ = self.ext._parse_initial_state(html)
        assert title == "测试视频标题"
        assert "https://sns-video-bd.xhscdn.com/stream/abc/h264.mp4" in candidates
        assert media_type == "video"

    def test_image_note_extracts_images(self):
        html = """
        <script>
        window.__INITIAL_STATE__ = {
          "note": {
            "noteDetailMap": {
              "abc123": {
                "note": {
                  "type": "normal",
                  "title": "图文笔记",
                  "imageList": [
                    {"url": "http://sns-webpic.xhscdn.com/img1.jpg", "infoList": [{"imageScene": "H5_DTL", "url": "http://sns-webpic.xhscdn.com/img1_hd.jpg"}]},
                    {"url": "http://sns-webpic.xhscdn.com/img2.jpg", "infoList": [{"imageScene": "H5_DTL", "url": "http://sns-webpic.xhscdn.com/img2_hd.jpg"}]}
                  ]
                }
              }
            }
          }
        };
        </script>
        """
        title, candidates, media_type, image_urls = self.ext._parse_initial_state(html)
        assert title == "图文笔记"
        assert media_type == "image"
        assert len(image_urls) == 2
        assert image_urls[0] == "https://sns-webpic.xhscdn.com/img1_hd.jpg"
        assert candidates == []

    def test_image_note_skipped(self):
        """图文笔记无 imageList 时返回空。"""
        html = """
        <script>
        window.__INITIAL_STATE__ = {
          "note": {
            "noteDetailMap": {
              "abc123": {
                "note": {
                  "type": "normal",
                  "title": "图文笔记"
                }
              }
            }
          }
        };
        </script>
        """
        _, candidates, media_type, image_urls = self.ext._parse_initial_state(html)
        assert candidates == []
        assert image_urls == []

    def test_multiple_codecs_collected(self):
        html = """
        <script>
        window.__INITIAL_STATE__ = {
          "note": {
            "noteDetailMap": {
              "abc123": {
                "note": {
                  "type": "video",
                  "title": "多码率",
                  "video": {
                    "media": {
                      "stream": {
                        "h264": [{"masterUrl": "https://cdn.xhscdn.com/h264.mp4"}],
                        "h265": [{"masterUrl": "https://cdn.xhscdn.com/h265.mp4"}]
                      }
                    }
                  }
                }
              }
            }
          }
        };
        </script>
        """
        _, candidates, _, _ = self.ext._parse_initial_state(html)
        assert len(candidates) == 2
        assert candidates[0].endswith("h264.mp4")

    def test_deduplication(self):
        html = """
        <script>
        window.__INITIAL_STATE__ = {
          "note": {
            "noteDetailMap": {
              "a": {"note": {"type": "video", "video": {"media": {"stream": {"h264": [{"masterUrl": "https://cdn.xhscdn.com/v.mp4"}]}}}}},
              "b": {"note": {"type": "video", "video": {"media": {"stream": {"h264": [{"masterUrl": "https://cdn.xhscdn.com/v.mp4"}]}}}}}
            }
          }
        };
        </script>
        """
        _, candidates, _, _ = self.ext._parse_initial_state(html)
        assert len(candidates) == 1

    def test_handles_undefined_values(self):
        html = """
        <script>
        window.__INITIAL_STATE__ = {
          "note": {"noteDetailMap": {}},
          "someKey": undefined
        };
        </script>
        """
        title, candidates, _, _ = self.ext._parse_initial_state(html)
        assert candidates == []

    def test_no_initial_state(self):
        title, candidates, _, _ = self.ext._parse_initial_state("<html>nothing</html>")
        assert title is None
        assert candidates == []

    def test_invalid_json(self):
        html = "<script>window.__INITIAL_STATE__ = {invalid json};</script>"
        _, candidates, _, _ = self.ext._parse_initial_state(html)
        assert candidates == []

    def test_title_from_desc_fallback(self):
        html = """
        <script>
        window.__INITIAL_STATE__ = {
          "note": {
            "noteDetailMap": {
              "abc123": {
                "note": {
                  "type": "video",
                  "desc": "描述文字",
                  "video": {
                    "media": {
                      "stream": {
                        "h264": [{"masterUrl": "https://cdn.xhscdn.com/v.mp4"}]
                      }
                    }
                  }
                }
              }
            }
          }
        };
        </script>
        """
        title, _, _, _ = self.ext._parse_initial_state(html)
        assert title == "描述文字"


class TestParseRawHtml:
    """原始 HTML 正则兜底解析。"""

    def setup_method(self):
        self.ext = XiaohongshuExtractor()

    def test_xhscdn_mp4_url(self):
        html = 'src="https://sns-video-bd.xhscdn.com/stream/abc/video.mp4?auth=xyz"'
        candidates = self.ext._parse_raw_html(html)
        assert any("xhscdn.com" in c for c in candidates)

    def test_escaped_url(self):
        html = r'"masterUrl":"https:\/\/sns-video-hw.xhscdn.com\/stream\/abc\/video.mp4"'
        candidates = self.ext._parse_raw_html(html)
        assert any("sns-video-hw.xhscdn.com" in c for c in candidates)

    def test_xhscdn_net_url(self):
        html = '"url": "https://sns-video-bd.xhscdn.net/stream/video.mp4"'
        candidates = self.ext._parse_raw_html(html)
        assert any("xhscdn.net" in c for c in candidates)

    def test_non_video_url_excluded(self):
        html = 'src="https://sns-webpic.xhscdn.com/img/thumbnail.jpg"'
        candidates = self.ext._parse_raw_html(html)
        assert candidates == []

    def test_no_match(self):
        assert self.ext._parse_raw_html("<html>no video</html>") == []


class TestRegistryIntegration:
    """确认 XiaohongshuExtractor 已注册到 registry。"""

    def test_xiaohongshu_extractor_registered(self):
        from app.extractors.registry import ExtractorRegistry
        registry = ExtractorRegistry()
        platforms = [e.platform for e in registry.extractors]
        assert "xiaohongshu" in platforms
        assert "douyin" in platforms
        assert "kuaishou" in platforms

    def test_douyin_does_not_claim_xhs_url(self):
        from app.extractors.douyin import DouyinExtractor
        ext = DouyinExtractor()
        assert ext.extract_url("http://xhslink.com/o/2z7YRSHBEWZ 小红书") is None

    def test_kuaishou_does_not_claim_xhs_url(self):
        from app.extractors.kuaishou import KuaishouExtractor
        ext = KuaishouExtractor()
        assert ext.extract_url("http://xhslink.com/o/2z7YRSHBEWZ 小红书") is None
