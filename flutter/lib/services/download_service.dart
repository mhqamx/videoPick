import 'dart:convert';
import 'dart:io';
import 'package:cupertino_http/cupertino_http.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import '../models/video_info.dart';
import '../models/download_error.dart';
import 'cookie_store.dart';

typedef ProgressCallback = void Function(double progress);

class DownloadService {
  static final DownloadService _instance = DownloadService._();
  factory DownloadService() => _instance;
  DownloadService._();

  /// Use CupertinoClient on iOS (respects system proxy/VPN via URLSession),
  /// fall back to default IOClient on other platforms.
  http.Client _createNativeClient() {
    if (Platform.isIOS || Platform.isMacOS) {
      return CupertinoClient.defaultSessionConfiguration();
    }
    return http.Client();
  }

  late final http.Client _client = _createNativeClient();

  static const _backendURLs = [
    'http://192.168.1.100:8000/resolve',
    'https://super-halibut-r4r59wg9qw93pv6p-8000.app.github.dev/resolve',
  ];

  static const _mobileUA =
      'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) '
      'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1';

  static const _desktopUA =
      'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) '
      'AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';

  // ── Public API ──

  Future<VideoInfo> parseAndDownload(
    String text, {
    ProgressCallback? onProgress,
  }) async {
    var url = _extractURL(text);
    if (url == null) throw DownloadError.invalidURL;
    url = _ensureHttps(url);

    VideoInfo info;

    if (_isDouyinURL(url)) {
      try {
        info = await _resolveDouyinLocally(url);
      } catch (e, st) {
        debugPrint('⚠️ Douyin local parse failed: $e');
        debugPrint('$st');
        info = await _resolveViaBackend(text);
      }
    } else if (_isInstagramURL(url)) {
      info = await _resolveInstagramLocally(url);
    } else if (_isXURL(url)) {
      info = await _resolveXLocally(url);
    } else if (_isXiaohongshuURL(url)) {
      try {
        info = await _resolveXiaohongshuLocally(url);
      } catch (_) {
        info = await _resolveViaBackend(text);
      }
    } else if (_isKuaishouURL(url)) {
      try {
        info = await _resolveKuaishouLocally(url);
      } catch (_) {
        info = await _resolveViaBackend(text);
      }
    } else {
      info = await _resolveViaBackend(text);
    }

    // Ensure all URLs use HTTPS (iOS ATS blocks plain HTTP)
    info.imageUrls = info.imageUrls.map(_ensureHttps).toList();

    // Download media
    if (info.mediaType == MediaType.images && info.imageUrls.isNotEmpty) {
      final paths = <String>[];
      for (var i = 0; i < info.imageUrls.length; i++) {
        final ext = _guessImageExt(info.imageUrls[i]);
        final fileName = '${info.id}_$i.$ext';
        final path = await _downloadFile(
          info.imageUrls[i],
          fileName,
          url,
          onProgress: (p) {
            onProgress?.call((i + p) / info.imageUrls.length);
          },
        );
        paths.add(path);
      }
      info.localImagePaths = paths;
    } else {
      final fileName = '${info.id}.mp4';
      final path = await _downloadFile(
        _ensureHttps(info.downloadUrl),
        fileName,
        url,
        onProgress: onProgress,
      );
      info.localPath = path;
    }

    return info;
  }

  // ── URL Utilities ──

  String? _extractURL(String text) {
    final regex = RegExp(r'https?://[^\s<>"{}|\\^`\[\]]+');
    final match = regex.firstMatch(text);
    return match?.group(0);
  }

  bool _isDouyinURL(String url) =>
      url.contains('douyin.com') || url.contains('iesdouyin.com');

  bool _isInstagramURL(String url) => url.contains('instagram.com');

  bool _isXURL(String url) =>
      url.contains('x.com') || url.contains('twitter.com');

  bool _isXiaohongshuURL(String url) =>
      url.contains('xiaohongshu.com') || url.contains('xhslink.com');

  bool _isKuaishouURL(String url) => url.contains('kuaishou.com');

  // ── Douyin Local Parsing ──

  /// Follow redirects manually using the http package (uses system network stack
  /// on iOS, which respects proxy/VPN settings unlike dart:io HttpClient).
  Future<({String body, String finalUrl})> _httpGetFollowRedirects(
    String url, {
    Map<String, String>? headers,
    int maxRedirects = 10,
  }) async {
    var currentUrl = _ensureHttps(url);
    final hdrs = {
      'User-Agent': _mobileUA,
      ...?headers,
    };

    for (var i = 0; i < maxRedirects; i++) {
      final resp = await _client
          .get(Uri.parse(currentUrl), headers: hdrs)
          .timeout(const Duration(seconds: 15));

      if (resp.statusCode >= 300 &&
          resp.statusCode < 400 &&
          resp.headers['location'] != null) {
        final location = resp.headers['location']!;
        currentUrl = _ensureHttps(location.startsWith('http')
            ? location
            : Uri.parse(currentUrl).resolve(location).toString());
        continue;
      }

      return (body: resp.body, finalUrl: currentUrl);
    }

    throw const DownloadError('重定向次数超出限制');
  }

  Future<VideoInfo> _resolveDouyinLocally(String url) async {
    final result = await _httpGetFollowRedirects(url);
    final html = result.body;
    final finalUrl = result.finalUrl;

      // Extract video ID
      final idMatch = RegExp(r'/video/(\d+)').firstMatch(finalUrl) ??
          RegExp(r'/note/(\d+)').firstMatch(finalUrl);
      final videoId = idMatch?.group(1) ?? 'douyin_${DateTime.now().millisecondsSinceEpoch}';

      // Try _ROUTER_DATA
      var jsonStr = _extractJSVariable(html, 'window._ROUTER_DATA');
      jsonStr ??= _extractJSVariable(html, 'window._SSR_HYDRATED_DATA');

      // Try RENDER_DATA
      if (jsonStr == null) {
        final renderMatch =
            RegExp(r'<script[^>]*id="RENDER_DATA"[^>]*>(.*?)</script>')
                .firstMatch(html);
        if (renderMatch != null) {
          jsonStr = Uri.decodeFull(renderMatch.group(1)!);
        }
      }

      if (jsonStr != null) {
        final json = jsonDecode(jsonStr);
        return _parseDouyinJson(json, videoId);
      }

      // Regex fallback
      final videoUrlMatch =
          RegExp(r'"playApi"\s*:\s*"(https?://[^"]+)"').firstMatch(html) ??
              RegExp(r'"play_addr"[^}]*"url_list"\s*:\s*\["(https?://[^"]+)"')
                  .firstMatch(html);
      if (videoUrlMatch != null) {
        final videoUrl = _normalizeDouyinVideoUrl(videoUrlMatch.group(1)!);
        return VideoInfo(id: videoId, downloadUrl: videoUrl);
      }

      throw DownloadError.noVideoLinkFound;
  }

  VideoInfo _parseDouyinJson(dynamic json, String videoId) {
    // Try loaderData path
    if (json is Map) {
      final loaderData = json['loaderData'];
      if (loaderData is Map) {
        for (final value in loaderData.values) {
          if (value is Map) {
            final itemList = _deepGet(value, ['videoInfoRes', 'item_list']);
            if (itemList is List && itemList.isNotEmpty) {
              return _extractDouyinItem(itemList[0], videoId);
            }
          }
        }
      }
    }

    // Try finding images dict (image post)
    final imagesDict = _findKey(json, 'images');
    if (imagesDict is List && imagesDict.isNotEmpty) {
      final urls = <String>[];
      for (final img in imagesDict) {
        if (img is Map) {
          final urlList = img['url_list'];
          if (urlList is List && urlList.isNotEmpty) {
            urls.add(urlList.last as String);
          }
        }
      }
      if (urls.isNotEmpty) {
        return VideoInfo(
          id: videoId,
          downloadUrl: '',
          mediaType: MediaType.images,
          imageUrls: urls,
        );
      }
    }

    // Try finding video dict
    final videoDict = _findKey(json, 'video');
    if (videoDict is Map) {
      final playAddr = videoDict['play_addr'];
      if (playAddr is Map) {
        final urlList = playAddr['url_list'];
        if (urlList is List && urlList.isNotEmpty) {
          return VideoInfo(
            id: videoId,
            downloadUrl: _normalizeDouyinVideoUrl(urlList[0] as String),
          );
        }
      }
    }

    // Try play_addr.url_list directly
    final playAddr = _findKey(json, 'play_addr');
    if (playAddr is Map) {
      final urlList = playAddr['url_list'];
      if (urlList is List && urlList.isNotEmpty) {
        return VideoInfo(
          id: videoId,
          downloadUrl: _normalizeDouyinVideoUrl(urlList[0] as String),
        );
      }
    }

    throw DownloadError.noVideoLinkFound;
  }

  VideoInfo _extractDouyinItem(Map<String, dynamic> item, String videoId) {
    // Check image post
    final awemeType = item['aweme_type']?.toString();
    final images = item['images'];
    if (awemeType == '2' || (images is List && images.isNotEmpty)) {
      final urls = <String>[];
      for (final img in (images as List)) {
        if (img is Map) {
          final urlList = img['url_list'];
          if (urlList is List && urlList.isNotEmpty) {
            urls.add(urlList.last as String);
          }
        }
      }
      if (urls.isNotEmpty) {
        return VideoInfo(
          id: videoId,
          title: item['desc'] as String?,
          downloadUrl: '',
          mediaType: MediaType.images,
          imageUrls: urls,
        );
      }
    }

    // Video post
    final video = item['video'];
    if (video is Map) {
      final playAddr = video['play_addr'];
      if (playAddr is Map) {
        final urlList = playAddr['url_list'];
        if (urlList is List && urlList.isNotEmpty) {
          return VideoInfo(
            id: videoId,
            title: item['desc'] as String?,
            downloadUrl: _normalizeDouyinVideoUrl(urlList[0] as String),
          );
        }
      }
    }

    throw DownloadError.noVideoLinkFound;
  }

  String _normalizeDouyinVideoUrl(String url) {
    var result = url.replaceAll('/playwm/', '/play/');
    final uri = Uri.tryParse(result);
    if (uri != null) {
      final params = Map<String, String>.from(uri.queryParameters)
        ..remove('watermark')
        ..remove('logo_name');
      result = uri.replace(queryParameters: params.isEmpty ? null : params).toString();
    }
    return result;
  }

  // ── Instagram Local Parsing ──

  Future<VideoInfo> _resolveInstagramLocally(String url) async {
    final cookies = await CookieStore.getCookies('instagram');
    if (cookies.isEmpty || cookies['sessionid'] == null) {
      throw const DownloadError('Instagram 需要配置 Cookie 才能使用');
    }

    final cookieStr =
        cookies.entries.map((e) => '${e.key}=${e.value}').join('; ');

    // Extract shortcode
    final scMatch =
        RegExp(r'/(reel|p|tv)/([A-Za-z0-9_-]+)').firstMatch(url);
    if (scMatch == null) throw DownloadError.invalidURL;
    final shortcode = scMatch.group(2)!;

    // Try oembed + media info API
    try {
      final oembedResp = await _client.get(
        Uri.parse(
            'https://www.instagram.com/api/v1/oembed/?url=https://www.instagram.com/p/$shortcode/'),
        headers: {
          'User-Agent': _desktopUA,
          'Cookie': cookieStr,
        },
      );
      if (oembedResp.statusCode == 200) {
        final oembedJson = jsonDecode(oembedResp.body);
        final mediaId = oembedJson['media_id']?.toString();
        if (mediaId != null) {
          final infoResp = await _client.get(
            Uri.parse(
                'https://www.instagram.com/api/v1/media/$mediaId/info/'),
            headers: {
              'User-Agent': _desktopUA,
              'Cookie': cookieStr,
              'X-CSRFToken': cookies['csrftoken'] ?? '',
            },
          );
          if (infoResp.statusCode == 200) {
            final infoJson = jsonDecode(infoResp.body);
            final result = _extractInstagramMedia(infoJson, shortcode);
            if (result != null) return result;
          }
        }
      }
    } catch (_) {}

    // Fallback: embed page
    for (final prefix in ['reel', 'p', 'tv']) {
      try {
        final embedResp = await _client.get(
          Uri.parse('https://www.instagram.com/$prefix/$shortcode/embed/'),
          headers: {'User-Agent': _desktopUA},
        );
        if (embedResp.statusCode == 200) {
          final videoMatch =
              RegExp(r'"video_url"\s*:\s*"(https?://[^"]+)"')
                  .firstMatch(embedResp.body);
          if (videoMatch != null) {
            final videoUrl =
                videoMatch.group(1)!.replaceAll(r'\u0026', '&');
            return VideoInfo(id: shortcode, downloadUrl: videoUrl);
          }
        }
      } catch (_) {}
    }

    throw const DownloadError('Instagram 解析失败');
  }

  VideoInfo? _extractInstagramMedia(dynamic json, String shortcode) {
    final items = json['items'] as List?;
    if (items == null || items.isEmpty) return null;
    final item = items[0] as Map<String, dynamic>;

    // Carousel (images)
    final carouselMedia = item['carousel_media'] as List?;
    if (carouselMedia != null && carouselMedia.isNotEmpty) {
      final urls = <String>[];
      for (final m in carouselMedia) {
        // Try video first
        final videoVersions = m['video_versions'] as List?;
        if (videoVersions != null && videoVersions.isNotEmpty) {
          urls.add(videoVersions[0]['url'] as String);
          continue;
        }
        // Then image
        final candidates =
            _deepGet(m, ['image_versions2', 'candidates']) as List?;
        if (candidates != null && candidates.isNotEmpty) {
          // Select highest resolution
          var best = candidates[0];
          var bestArea = (best['width'] as int) * (best['height'] as int);
          for (final c in candidates) {
            final area = (c['width'] as int) * (c['height'] as int);
            if (area > bestArea) {
              best = c;
              bestArea = area;
            }
          }
          urls.add(best['url'] as String);
        }
      }
      if (urls.isNotEmpty) {
        return VideoInfo(
          id: shortcode,
          title: (item['caption'] as Map?)?['text'] as String?,
          downloadUrl: '',
          mediaType: MediaType.images,
          imageUrls: urls,
        );
      }
    }

    // Single video
    final videoVersions = item['video_versions'] as List?;
    if (videoVersions != null && videoVersions.isNotEmpty) {
      return VideoInfo(
        id: shortcode,
        title: (item['caption'] as Map?)?['text'] as String?,
        downloadUrl: videoVersions[0]['url'] as String,
      );
    }

    // Single image
    final candidates =
        _deepGet(item, ['image_versions2', 'candidates']) as List?;
    if (candidates != null && candidates.isNotEmpty) {
      return VideoInfo(
        id: shortcode,
        title: (item['caption'] as Map?)?['text'] as String?,
        downloadUrl: '',
        mediaType: MediaType.images,
        imageUrls: [candidates[0]['url'] as String],
      );
    }

    return null;
  }

  // ── X (Twitter) Local Parsing ──

  String? _cachedQueryId;
  String? _cachedBearerToken;
  DateTime? _cacheTime;

  Future<VideoInfo> _resolveXLocally(String url) async {
    final cookies = await CookieStore.getCookies('x');
    if (cookies.isEmpty ||
        cookies['auth_token'] == null ||
        cookies['ct0'] == null) {
      throw const DownloadError('X (Twitter) 需要配置 Cookie 才能使用');
    }

    // Extract tweet ID
    final idMatch = RegExp(r'/status/(\d+)').firstMatch(url);
    if (idMatch == null) throw DownloadError.invalidURL;
    final tweetId = idMatch.group(1)!;

    // Get or refresh metadata
    await _ensureXMetadata(cookies);

    final cookieStr =
        cookies.entries.map((e) => '${e.key}=${e.value}').join('; ');

    final variables = jsonEncode({
      'tweetId': tweetId,
      'withCommunity': false,
      'includePromotedContent': false,
      'withVoice': false,
    });
    final features = jsonEncode({
      'creator_subscriptions_tweet_preview_api_enabled': true,
      'premium_content_api_read_enabled': false,
      'communities_web_enable_tweet_community_results_fetch': true,
      'c9s_tweet_anatomy_moderator_badge_enabled': true,
      'responsive_web_edit_tweet_api_enabled': true,
      'graphql_is_translatable_rweb_tweet_is_translatable_enabled': true,
      'view_counts_everywhere_api_enabled': true,
      'longform_notetweets_consumption_enabled': true,
      'responsive_web_twitter_article_tweet_consumption_enabled': true,
      'tweet_awards_web_tipping_enabled': false,
      'creator_subscriptions_quote_tweet_preview_enabled': false,
      'freedom_of_speech_not_reach_fetch_enabled': true,
      'standardized_nudges_misinfo': true,
      'tweet_with_visibility_results_prefer_gql_limited_actions_policy_enabled':
          true,
      'rweb_video_timestamps_enabled': true,
      'longform_notetweets_rich_text_read_enabled': true,
      'longform_notetweets_inline_media_enabled': true,
      'responsive_web_enhance_cards_enabled': false,
      'responsive_web_graphql_exclude_directive_enabled': true,
      'verified_phone_label_enabled': false,
      'responsive_web_graphql_skip_user_profile_image_extensions_enabled':
          false,
      'responsive_web_graphql_timeline_navigation_enabled': true,
      'tweetypie_unmention_optimization_enabled': true,
    });

    final queryUrl =
        'https://x.com/i/api/graphql/$_cachedQueryId/TweetResultByRestId'
        '?variables=${Uri.encodeComponent(variables)}'
        '&features=${Uri.encodeComponent(features)}';

    final resp = await _client.get(
      Uri.parse(queryUrl),
      headers: {
        'User-Agent': _desktopUA,
        'Authorization': 'Bearer $_cachedBearerToken',
        'X-Csrf-Token': cookies['ct0']!,
        'Cookie': cookieStr,
      },
    );

    if (resp.statusCode != 200) {
      throw DownloadError.downloadFailed(resp.statusCode);
    }

    final json = jsonDecode(resp.body);
    return _extractXMedia(json, tweetId);
  }

  Future<void> _ensureXMetadata(Map<String, String> cookies) async {
    if (_cachedQueryId != null &&
        _cachedBearerToken != null &&
        _cacheTime != null &&
        DateTime.now().difference(_cacheTime!).inMinutes < 30) {
      return;
    }

    final cookieStr =
        cookies.entries.map((e) => '${e.key}=${e.value}').join('; ');

    // Load X page to find main.js
    final pageResp = await _client.get(
      Uri.parse('https://x.com/i/flow/login'),
      headers: {
        'User-Agent': _desktopUA,
        'Cookie': cookieStr,
      },
    );

    final jsMatch = RegExp(r'https://abs\.twimg\.com/responsive-web/client-web[^"]*main\.[a-f0-9]+\.js')
        .firstMatch(pageResp.body);
    if (jsMatch == null) {
      throw const DownloadError('无法获取 X 元数据');
    }

    final jsResp = await _client.get(Uri.parse(jsMatch.group(0)!));
    final jsContent = jsResp.body;

    // Extract queryId
    final queryIdMatch =
        RegExp(r'queryId:"([A-Za-z0-9_-]{20,})"[^}]*operationName:"TweetResultByRestId"')
            .firstMatch(jsContent);

    // Extract bearer token
    final bearerMatch =
        RegExp(r'"(AAAAAA[A-Za-z0-9%]+)"').firstMatch(jsContent);

    if (queryIdMatch == null || bearerMatch == null) {
      throw const DownloadError('无法从 X 提取认证信息');
    }

    _cachedQueryId = queryIdMatch.group(1);
    _cachedBearerToken = bearerMatch.group(1);
    _cacheTime = DateTime.now();
  }

  VideoInfo _extractXMedia(dynamic json, String tweetId) {
    final result = _deepGet(json, [
      'data', 'tweetResult', 'result'
    ]);

    if (result == null) throw DownloadError.videoDataNotFound;

    // Handle tweet with tombstone or __typename == 'TweetWithVisibilityResults'
    dynamic tweetData = result;
    if (result is Map && result['tweet'] != null) {
      tweetData = result['tweet'];
    }

    final legacy = tweetData['legacy'] as Map<String, dynamic>?;
    final fullText = legacy?['full_text'] as String?;

    final extMedia = _deepGet(legacy, ['extended_entities', 'media']) as List?;
    if (extMedia == null || extMedia.isEmpty) {
      throw DownloadError.noVideoLinkFound;
    }

    // Check for videos
    final videos = <Map<String, dynamic>>[];
    final photos = <String>[];

    for (final m in extMedia) {
      final type = m['type'] as String?;
      if (type == 'video' || type == 'animated_gif') {
        final variants = _deepGet(m, ['video_info', 'variants']) as List?;
        if (variants != null) {
          // Filter mp4 with bitrate, sort by bitrate desc
          final mp4s = variants
              .where((v) =>
                  v['content_type'] == 'video/mp4' && v['bitrate'] != null)
              .toList()
            ..sort((a, b) =>
                (b['bitrate'] as int).compareTo(a['bitrate'] as int));
          if (mp4s.isNotEmpty) {
            videos.add(mp4s.first as Map<String, dynamic>);
          }
        }
      } else if (type == 'photo') {
        final photoUrl = m['media_url_https'] as String?;
        if (photoUrl != null && photoUrl.contains('pbs.twimg.com')) {
          photos.add(photoUrl);
        }
      }
    }

    if (videos.isNotEmpty) {
      return VideoInfo(
        id: tweetId,
        title: fullText,
        downloadUrl: videos.first['url'] as String,
      );
    }

    if (photos.isNotEmpty) {
      return VideoInfo(
        id: tweetId,
        title: fullText,
        downloadUrl: '',
        mediaType: MediaType.images,
        imageUrls: photos,
      );
    }

    throw DownloadError.noVideoLinkFound;
  }

  // ── Xiaohongshu Local Parsing ──

  Future<VideoInfo> _resolveXiaohongshuLocally(String url) async {
    final result = await _httpGetFollowRedirects(url);
    final html = result.body;
    final finalUrl = result.finalUrl;
    {

      final idMatch = RegExp(r'/explore/([a-f0-9]+)').firstMatch(finalUrl) ??
          RegExp(r'/discovery/item/([a-f0-9]+)').firstMatch(finalUrl);
      final noteId = idMatch?.group(1) ?? 'xhs_${DateTime.now().millisecondsSinceEpoch}';

      final jsonStr = _extractBracketJson(html, 'window.__INITIAL_STATE__');
      if (jsonStr != null) {
        // Replace undefined with null for valid JSON
        final cleaned = jsonStr.replaceAll(RegExp(r':\s*undefined'), ': null');
        final json = jsonDecode(cleaned);

        // Try noteData path
        final noteData = _deepGet(json, ['noteData', 'data', 'noteData']) ??
            _findNoteInMap(json);

        if (noteData is Map) {
          final type = noteData['type'] as String?;
          final title = noteData['title'] as String?;

          if (type == 'normal') {
            // Image note
            final imageList = noteData['imageList'] as List?;
            if (imageList != null) {
              final urls = <String>[];
              for (final img in imageList) {
                final infoList = img['infoList'] as List?;
                if (infoList != null) {
                  // Prefer H5_DTL scene
                  String? bestUrl;
                  for (final info in infoList) {
                    final imgUrl = info['url'] as String?;
                    if (imgUrl != null) {
                      if (info['imageScene'] == 'H5_DTL') {
                        bestUrl = imgUrl;
                        break;
                      }
                      bestUrl ??= imgUrl;
                    }
                  }
                  if (bestUrl != null) {
                    urls.add(bestUrl);
                  }
                }
              }
              if (urls.isNotEmpty) {
                return VideoInfo(
                  id: noteId,
                  title: title,
                  downloadUrl: '',
                  mediaType: MediaType.images,
                  imageUrls: urls,
                );
              }
            }
          } else if (type == 'video') {
            // Video note
            final stream = _deepGet(noteData, ['video', 'media', 'stream']);
            if (stream is Map) {
              for (final codec in ['h264', 'h265', 'av1']) {
                final codecStreams = stream[codec] as List?;
                if (codecStreams != null && codecStreams.isNotEmpty) {
                  final masterUrl = codecStreams[0]['masterUrl'] as String?;
                  if (masterUrl != null) {
                    return VideoInfo(
                      id: noteId,
                      title: title,
                      downloadUrl: masterUrl,
                    );
                  }
                }
              }
            }
          }
        }
      }

      // Regex fallback
      final cdnMatch =
          RegExp(r'https?://[^\s"]*xhscdn[^\s"]*').firstMatch(html);
      if (cdnMatch != null) {
        return VideoInfo(id: noteId, downloadUrl: cdnMatch.group(0)!);
      }

      throw DownloadError.noVideoLinkFound;
    }
  }

  Map<String, dynamic>? _findNoteInMap(dynamic json) {
    if (json is! Map) return null;
    final noteDetailMap = json['note']?['noteDetailMap'];
    if (noteDetailMap is Map && noteDetailMap.isNotEmpty) {
      final first = noteDetailMap.values.first;
      if (first is Map && first['note'] is Map) {
        return first['note'] as Map<String, dynamic>;
      }
    }
    return null;
  }

  // ── Kuaishou Local Parsing ──

  Future<VideoInfo> _resolveKuaishouLocally(String url) async {
    final result = await _httpGetFollowRedirects(url);
    final html = result.body;
    final finalUrl = result.finalUrl;
    {

      final idMatch =
          RegExp(r'/short-video/([A-Za-z0-9]+)').firstMatch(finalUrl) ??
              RegExp(r'/fw/photo/([A-Za-z0-9]+)').firstMatch(finalUrl);
      final photoId = idMatch?.group(1) ?? 'ks_${DateTime.now().millisecondsSinceEpoch}';

      // Try API first
      try {
        final apiResp = await _client.post(
          Uri.parse(
              'https://m.kuaishou.com/rest/wd/ugH5App/photo/simple/info'),
          headers: {
            'Content-Type': 'application/json',
            'User-Agent': _mobileUA,
            'Referer': 'https://m.kuaishou.com/',
          },
          body: jsonEncode({
            'photoId': photoId,
            'isLongVideo': false,
          }),
        );
        if (apiResp.statusCode == 200) {
          final apiJson = jsonDecode(apiResp.body);
          final photo = apiJson['photo'];
          if (photo is Map) {
            final photoType = photo['photoType'] as String?;
            if (photoType == 'VERTICAL_ATLAS' ||
                photoType == 'HORIZONTAL_ATLAS' ||
                photoType == 'MULTI_IMAGE') {
              // Image atlas
              final atlas = photo['atlas'] as Map?;
              if (atlas != null) {
                final cdnList = atlas['cdnList'] as List?;
                final list = atlas['list'] as List?;
                if (cdnList != null &&
                    cdnList.isNotEmpty &&
                    list != null &&
                    list.isNotEmpty) {
                  final cdn = cdnList[0]['cdn'] as String;
                  final urls = list
                      .map((item) => 'https://$cdn${item as String}')
                      .toList();
                  return VideoInfo(
                    id: photoId,
                    title: photo['caption'] as String?,
                    downloadUrl: '',
                    mediaType: MediaType.images,
                    imageUrls: urls,
                  );
                }
              }
            }

            // Video
            final mainMvUrls = photo['mainMvUrls'] as List?;
            if (mainMvUrls != null && mainMvUrls.isNotEmpty) {
              return VideoInfo(
                id: photoId,
                title: photo['caption'] as String?,
                downloadUrl: mainMvUrls[0]['url'] as String,
              );
            }
          }
        }
      } catch (_) {}

      // Try __APOLLO_STATE__
      final apolloStr = _extractJSVariable(html, 'window.__APOLLO_STATE__');
      if (apolloStr != null) {
        final apolloJson = jsonDecode(apolloStr);
        if (apolloJson is Map) {
          for (final entry in apolloJson.entries) {
            if (entry.key.toString().contains('Photo') ||
                entry.key.toString().contains('Work') ||
                entry.key.toString().contains('Video')) {
              final val = entry.value;
              if (val is Map) {
                final videoUrl = val['videoUrl'] as String?;
                if (videoUrl != null) {
                  return VideoInfo(id: photoId, downloadUrl: videoUrl);
                }
              }
            }
          }
        }
      }

      // Try __INITIAL_STATE__
      final initialStr = _extractJSVariable(html, 'window.__INITIAL_STATE__');
      if (initialStr != null) {
        final initialJson = jsonDecode(initialStr);
        final videoUrl = _findKey(initialJson, 'videoUrl') ??
            _findKey(initialJson, 'video_url') ??
            _findKey(initialJson, 'mp4Url');
        if (videoUrl is String && videoUrl.isNotEmpty) {
          return VideoInfo(id: photoId, downloadUrl: videoUrl);
        }
      }

      // Regex fallback
      final ksMatch =
          RegExp(r'https?://[^\s"]*(?:kwimgs|kwai\.net)[^\s"]*\.mp4[^\s"]*')
              .firstMatch(html);
      if (ksMatch != null) {
        return VideoInfo(id: photoId, downloadUrl: ksMatch.group(0)!);
      }

      throw DownloadError.noVideoLinkFound;
    }
  }

  // ── Backend Resolution ──

  Future<VideoInfo> _resolveViaBackend(String text) async {
    final cookies = await CookieStore.allCookies();
    final body = jsonEncode(ResolveRequest(text: text, cookies: cookies).toJson());

    String? lastError;
    for (final backendUrl in _backendURLs) {
      try {
        final resp = await http
            .post(
              Uri.parse(backendUrl),
              headers: {'Content-Type': 'application/json'},
              body: body,
            )
            .timeout(const Duration(seconds: 30));

        if (resp.statusCode == 200) {
          final json = jsonDecode(resp.body);
          final resolved = ResolveResponse.fromJson(json);
          final backendBase =
              backendUrl.replaceAll('/resolve', '');

          var downloadUrl = resolved.downloadUrl ?? '';
          if (downloadUrl.startsWith('/')) {
            downloadUrl = '$backendBase$downloadUrl';
          }
          downloadUrl = _normalizeBackendUrl(downloadUrl, backendBase);

          final isImage = resolved.mediaType == 'image';
          var imageUrls = resolved.imageUrls ?? [];
          imageUrls = imageUrls
              .map((u) => u.startsWith('/')
                  ? '$backendBase$u'
                  : _normalizeBackendUrl(u, backendBase))
              .toList();

          return VideoInfo(
            id: resolved.videoId ?? 'backend_${DateTime.now().millisecondsSinceEpoch}',
            title: resolved.title,
            downloadUrl: downloadUrl,
            mediaType: isImage ? MediaType.images : MediaType.video,
            imageUrls: imageUrls,
          );
        } else {
          try {
            final errJson = jsonDecode(resp.body);
            lastError = errJson['detail']?.toString() ?? resp.body;
          } catch (_) {
            lastError = 'HTTP ${resp.statusCode}';
          }
        }
      } catch (e) {
        lastError = e.toString();
      }
    }

    throw DownloadError.backendResolveFailed(lastError ?? '所有后端地址均不可用');
  }

  String _normalizeBackendUrl(String url, String backendBase) {
    final uri = Uri.tryParse(url);
    if (uri == null) return url;
    final host = uri.host;
    if (host == 'localhost' || host == '127.0.0.1' || host == '::1') {
      final backendUri = Uri.parse(backendBase);
      return uri
          .replace(
            scheme: backendUri.scheme,
            host: backendUri.host,
            port: backendUri.port,
          )
          .toString();
    }
    return url;
  }

  // ── Download ──

  Future<String> _downloadFile(
    String url,
    String fileName,
    String sourceUrl, {
    ProgressCallback? onProgress,
  }) async {
    final dir = await getTemporaryDirectory();
    final downloadDir = Directory('${dir.path}/downloads');
    if (!await downloadDir.exists()) {
      await downloadDir.create(recursive: true);
    }
    final filePath = '${downloadDir.path}/$fileName';

    final headers = _buildDownloadHeaders(url, sourceUrl);

    final request = http.Request('GET', Uri.parse(url));
    headers.forEach((k, v) => request.headers[k] = v);

    final streamedResp = await _client.send(request);
    if (streamedResp.statusCode != 200 && streamedResp.statusCode != 206) {
      throw DownloadError.downloadFailed(streamedResp.statusCode);
    }

    final totalBytes = streamedResp.contentLength ?? -1;
    var downloadedBytes = 0;

    final file = File(filePath);
    final sink = file.openWrite();

    await for (final chunk in streamedResp.stream) {
      sink.add(chunk);
      downloadedBytes += chunk.length;
      if (totalBytes > 0) {
        onProgress?.call(downloadedBytes / totalBytes);
      }
    }

    await sink.close();
    return filePath;
  }

  Map<String, String> _buildDownloadHeaders(String url, String sourceUrl) {
    final headers = <String, String>{
      'User-Agent': _mobileUA,
    };

    final uri = Uri.tryParse(url);
    if (uri == null) return headers;
    final host = uri.host;

    if (host.contains('instagram') ||
        host.contains('cdninstagram') ||
        host.contains('fbcdn')) {
      headers['Referer'] = 'https://www.instagram.com/';
    } else if (host.contains('twimg') ||
        host.contains('x.com') ||
        host.contains('twitter')) {
      headers['Referer'] = 'https://x.com/';
    } else if (host.contains('bilibili') ||
        host.contains('upos') ||
        host.contains('akamaized')) {
      headers['User-Agent'] = _desktopUA;
      headers['Referer'] = 'https://www.bilibili.com/';
    } else if (host.contains('xhscdn') || host.contains('xiaohongshu')) {
      headers['Referer'] = 'https://www.xiaohongshu.com/';
    } else if (host.contains('kwimgs') ||
        host.contains('kwai') ||
        host.contains('kuaishou') ||
        host.contains('yximgs')) {
      headers['Referer'] = 'https://www.kuaishou.com/';
    }

    return headers;
  }

  // ── JSON Helpers ──

  String? _extractJSVariable(String html, String varName) {
    final pattern = '$varName\\s*=\\s*';
    final match = RegExp(pattern).firstMatch(html);
    if (match == null) return null;

    final start = match.end;
    return _extractBalancedJson(html, start);
  }

  String? _extractBracketJson(String html, String varName) {
    final pattern = '$varName\\s*=\\s*';
    final match = RegExp(pattern).firstMatch(html);
    if (match == null) return null;
    final start = match.end;
    return _extractBalancedJson(html, start);
  }

  String? _extractBalancedJson(String html, int start) {
    if (start >= html.length) return null;
    final openChar = html[start];
    if (openChar != '{' && openChar != '[') return null;
    final closeChar = openChar == '{' ? '}' : ']';

    var depth = 0;
    var inString = false;
    var escape = false;

    for (var i = start; i < html.length; i++) {
      final c = html[i];

      if (escape) {
        escape = false;
        continue;
      }

      if (c == '\\' && inString) {
        escape = true;
        continue;
      }

      if (c == '"') {
        inString = !inString;
        continue;
      }

      if (inString) continue;

      if (c == openChar) {
        depth++;
      } else if (c == closeChar) {
        depth--;
        if (depth == 0) {
          return html.substring(start, i + 1);
        }
      }
    }
    return null;
  }

  dynamic _deepGet(dynamic obj, List<String> keys) {
    dynamic current = obj;
    for (final key in keys) {
      if (current is Map) {
        current = current[key];
      } else {
        return null;
      }
    }
    return current;
  }

  dynamic _findKey(dynamic obj, String key, {int depth = 0}) {
    if (depth > 15) return null;
    if (obj is Map) {
      if (obj.containsKey(key)) return obj[key];
      for (final value in obj.values) {
        final result = _findKey(value, key, depth: depth + 1);
        if (result != null) return result;
      }
    } else if (obj is List) {
      for (final item in obj) {
        final result = _findKey(item, key, depth: depth + 1);
        if (result != null) return result;
      }
    }
    return null;
  }

  /// Upgrade http:// to https:// for CDN URLs (iOS ATS blocks plain HTTP).
  String _ensureHttps(String url) {
    if (url.startsWith('http://')) {
      return url.replaceFirst('http://', 'https://');
    }
    if (url.startsWith('//')) {
      return 'https:$url';
    }
    return url;
  }

  String _guessImageExt(String url) {
    final lower = url.toLowerCase();
    if (lower.contains('.png')) return 'png';
    if (lower.contains('.webp')) return 'webp';
    if (lower.contains('.gif')) return 'gif';
    return 'jpg';
  }
}
