import RNFS from 'react-native-fs';
import {MediaType, VideoInfo, ResolveResponse} from '../models/VideoInfo';
import {CookieStore} from './CookieStore';

export type ProgressCallback = (progress: number) => void;

const BACKEND_URLS = [
  'http://192.168.1.100:8000/resolve',
  'https://super-halibut-r4r59wg9qw93pv6p-8000.app.github.dev/resolve',
];

const MOBILE_UA =
  'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) ' +
  'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1';

const DESKTOP_UA =
  'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) ' +
  'AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';

class DownloadServiceImpl {
  private cachedQueryId?: string;
  private cachedBearerToken?: string;
  private cacheTime?: Date;

  // ── Public API ──

  async parseAndDownload(
    text: string,
    onProgress?: ProgressCallback,
  ): Promise<VideoInfo> {
    let url = this.extractURL(text);
    if (!url) throw new Error('无法从输入中提取有效链接');
    url = ensureHttps(url);

    let info: VideoInfo;

    if (this.isDouyinURL(url)) {
      try {
        info = await this.resolveDouyinLocally(url);
      } catch (e) {
        console.warn('Douyin local parse failed:', e);
        info = await this.resolveViaBackend(text);
      }
    } else if (this.isInstagramURL(url)) {
      info = await this.resolveInstagramLocally(url);
    } else if (this.isXURL(url)) {
      info = await this.resolveXLocally(url);
    } else if (this.isXiaohongshuURL(url)) {
      try {
        info = await this.resolveXiaohongshuLocally(url);
      } catch {
        info = await this.resolveViaBackend(text);
      }
    } else if (this.isKuaishouURL(url)) {
      try {
        info = await this.resolveKuaishouLocally(url);
      } catch {
        info = await this.resolveViaBackend(text);
      }
    } else {
      info = await this.resolveViaBackend(text);
    }

    info.imageUrls = info.imageUrls.map(ensureHttps);

    // Download media
    if (info.mediaType === MediaType.images && info.imageUrls.length > 0) {
      const paths: string[] = [];
      for (let i = 0; i < info.imageUrls.length; i++) {
        const ext = guessImageExt(info.imageUrls[i]);
        const fileName = `${info.id}_${i}.${ext}`;
        const path = await this.downloadFile(
          info.imageUrls[i],
          fileName,
          url,
          (p: number) => onProgress?.((i + p) / info.imageUrls.length),
        );
        paths.push(path);
      }
      info.localImagePaths = paths;
    } else {
      const fileName = `${info.id}.mp4`;
      const path = await this.downloadFile(
        ensureHttps(info.downloadUrl),
        fileName,
        url,
        onProgress,
      );
      info.localPath = path;
    }

    return info;
  }

  // ── URL Utilities ──

  private extractURL(text: string): string | null {
    const match = text.match(/https?:\/\/[^\s<>"{}|\\^`[\]]+/);
    return match ? match[0] : null;
  }

  private isDouyinURL(url: string): boolean {
    return url.includes('douyin.com') || url.includes('iesdouyin.com');
  }

  private isInstagramURL(url: string): boolean {
    return url.includes('instagram.com');
  }

  private isXURL(url: string): boolean {
    return url.includes('x.com') || url.includes('twitter.com');
  }

  private isXiaohongshuURL(url: string): boolean {
    return url.includes('xiaohongshu.com') || url.includes('xhslink.com');
  }

  private isKuaishouURL(url: string): boolean {
    return url.includes('kuaishou.com');
  }

  // ── HTTP with redirect following ──

  private async httpGetFollowRedirects(
    url: string,
    headers?: Record<string, string>,
    maxRedirects = 10,
  ): Promise<{body: string; finalUrl: string}> {
    let currentUrl = ensureHttps(url);
    const hdrs: Record<string, string> = {
      'User-Agent': MOBILE_UA,
      ...headers,
    };

    for (let i = 0; i < maxRedirects; i++) {
      const resp = await fetch(currentUrl, {
        headers: hdrs,
        redirect: 'manual',
      });

      if (resp.status >= 300 && resp.status < 400) {
        const location = resp.headers.get('location');
        if (location) {
          currentUrl = ensureHttps(
            location.startsWith('http')
              ? location
              : new URL(location, currentUrl).toString(),
          );
          continue;
        }
      }

      return {body: await resp.text(), finalUrl: currentUrl};
    }

    throw new Error('重定向次数超出限制');
  }

  // ── Douyin Local Parsing ──

  private async resolveDouyinLocally(url: string): Promise<VideoInfo> {
    const result = await this.httpGetFollowRedirects(url);
    const {body: html, finalUrl} = result;

    const idMatch =
      finalUrl.match(/\/video\/(\d+)/) || finalUrl.match(/\/note\/(\d+)/);
    const videoId =
      idMatch?.[1] ?? `douyin_${Date.now()}`;

    // Try _ROUTER_DATA
    let jsonStr = extractJSVariable(html, 'window._ROUTER_DATA');
    if (!jsonStr) {
      jsonStr = extractJSVariable(html, 'window._SSR_HYDRATED_DATA');
    }

    // Try RENDER_DATA
    if (!jsonStr) {
      const renderMatch = html.match(
        /<script[^>]*id="RENDER_DATA"[^>]*>(.*?)<\/script>/,
      );
      if (renderMatch) {
        jsonStr = decodeURIComponent(renderMatch[1]);
      }
    }

    if (jsonStr) {
      const json = JSON.parse(jsonStr);
      return this.parseDouyinJson(json, videoId);
    }

    // Regex fallback
    const videoUrlMatch =
      html.match(/"playApi"\s*:\s*"(https?:\/\/[^"]+)"/) ||
      html.match(/"play_addr"[^}]*"url_list"\s*:\s*\["(https?:\/\/[^"]+)"/);
    if (videoUrlMatch) {
      const videoUrl = normalizeDouyinVideoUrl(videoUrlMatch[1]);
      return {
        id: videoId,
        downloadUrl: videoUrl,
        mediaType: MediaType.video,
        imageUrls: [],
        localImagePaths: [],
      };
    }

    throw new Error('解析失败：未找到视频链接');
  }

  private parseDouyinJson(json: any, videoId: string): VideoInfo {
    // Try loaderData path
    if (json && typeof json === 'object') {
      const loaderData = json.loaderData;
      if (loaderData && typeof loaderData === 'object') {
        for (const value of Object.values(loaderData) as any[]) {
          if (value && typeof value === 'object') {
            const itemList = deepGet(value, [
              'videoInfoRes',
              'item_list',
            ]);
            if (Array.isArray(itemList) && itemList.length > 0) {
              return this.extractDouyinItem(itemList[0], videoId);
            }
          }
        }
      }
    }

    // Try finding images (image post)
    const imagesDict = findKey(json, 'images');
    if (Array.isArray(imagesDict) && imagesDict.length > 0) {
      const urls: string[] = [];
      for (const img of imagesDict) {
        if (img && typeof img === 'object') {
          const urlList = img.url_list;
          if (Array.isArray(urlList) && urlList.length > 0) {
            urls.push(urlList[urlList.length - 1]);
          }
        }
      }
      if (urls.length > 0) {
        return {
          id: videoId,
          downloadUrl: '',
          mediaType: MediaType.images,
          imageUrls: urls,
          localImagePaths: [],
        };
      }
    }

    // Try finding video dict
    const videoDict = findKey(json, 'video');
    if (videoDict && typeof videoDict === 'object') {
      const playAddr = videoDict.play_addr;
      if (playAddr && typeof playAddr === 'object') {
        const urlList = playAddr.url_list;
        if (Array.isArray(urlList) && urlList.length > 0) {
          return {
            id: videoId,
            downloadUrl: normalizeDouyinVideoUrl(urlList[0]),
            mediaType: MediaType.video,
            imageUrls: [],
            localImagePaths: [],
          };
        }
      }
    }

    // Try play_addr.url_list directly
    const playAddr = findKey(json, 'play_addr');
    if (playAddr && typeof playAddr === 'object') {
      const urlList = playAddr.url_list;
      if (Array.isArray(urlList) && urlList.length > 0) {
        return {
          id: videoId,
          downloadUrl: normalizeDouyinVideoUrl(urlList[0]),
          mediaType: MediaType.video,
          imageUrls: [],
          localImagePaths: [],
        };
      }
    }

    throw new Error('解析失败：未找到视频链接');
  }

  private extractDouyinItem(item: any, videoId: string): VideoInfo {
    const awemeType = item.aweme_type?.toString();
    const images = item.images;
    if (awemeType === '2' || (Array.isArray(images) && images.length > 0)) {
      const urls: string[] = [];
      for (const img of images ?? []) {
        if (img && typeof img === 'object') {
          const urlList = img.url_list;
          if (Array.isArray(urlList) && urlList.length > 0) {
            urls.push(urlList[urlList.length - 1]);
          }
        }
      }
      if (urls.length > 0) {
        return {
          id: videoId,
          title: item.desc,
          downloadUrl: '',
          mediaType: MediaType.images,
          imageUrls: urls,
          localImagePaths: [],
        };
      }
    }

    const video = item.video;
    if (video && typeof video === 'object') {
      const playAddr = video.play_addr;
      if (playAddr && typeof playAddr === 'object') {
        const urlList = playAddr.url_list;
        if (Array.isArray(urlList) && urlList.length > 0) {
          return {
            id: videoId,
            title: item.desc,
            downloadUrl: normalizeDouyinVideoUrl(urlList[0]),
            mediaType: MediaType.video,
            imageUrls: [],
            localImagePaths: [],
          };
        }
      }
    }

    throw new Error('解析失败：未找到视频链接');
  }

  // ── Instagram Local Parsing ──

  private async resolveInstagramLocally(url: string): Promise<VideoInfo> {
    const cookies = await CookieStore.getCookies('instagram');
    if (!cookies.sessionid) {
      throw new Error('Instagram 需要配置 Cookie 才能使用');
    }

    const cookieStr = Object.entries(cookies)
      .map(([k, v]) => `${k}=${v}`)
      .join('; ');

    const scMatch = url.match(/\/(reel|p|tv)\/([A-Za-z0-9_-]+)/);
    if (!scMatch) throw new Error('无法从输入中提取有效链接');
    const shortcode = scMatch[2];

    // Try oembed + media info API
    try {
      const oembedResp = await fetch(
        `https://www.instagram.com/api/v1/oembed/?url=https://www.instagram.com/p/${shortcode}/`,
        {headers: {'User-Agent': DESKTOP_UA, Cookie: cookieStr}},
      );
      if (oembedResp.ok) {
        const oembedJson = await oembedResp.json();
        const mediaId = oembedJson.media_id?.toString();
        if (mediaId) {
          const infoResp = await fetch(
            `https://www.instagram.com/api/v1/media/${mediaId}/info/`,
            {
              headers: {
                'User-Agent': DESKTOP_UA,
                Cookie: cookieStr,
                'X-CSRFToken': cookies.csrftoken ?? '',
              },
            },
          );
          if (infoResp.ok) {
            const infoJson = await infoResp.json();
            const result = this.extractInstagramMedia(infoJson, shortcode);
            if (result) return result;
          }
        }
      }
    } catch {}

    // Fallback: embed page
    for (const prefix of ['reel', 'p', 'tv']) {
      try {
        const embedResp = await fetch(
          `https://www.instagram.com/${prefix}/${shortcode}/embed/`,
          {headers: {'User-Agent': DESKTOP_UA}},
        );
        if (embedResp.ok) {
          const embedHtml = await embedResp.text();
          const videoMatch = embedHtml.match(
            /"video_url"\s*:\s*"(https?:\/\/[^"]+)"/,
          );
          if (videoMatch) {
            const videoUrl = videoMatch[1].replace(/\\u0026/g, '&');
            return {
              id: shortcode,
              downloadUrl: videoUrl,
              mediaType: MediaType.video,
              imageUrls: [],
              localImagePaths: [],
            };
          }
        }
      } catch {}
    }

    throw new Error('Instagram 解析失败');
  }

  private extractInstagramMedia(
    json: any,
    shortcode: string,
  ): VideoInfo | null {
    const items = json.items as any[];
    if (!items || items.length === 0) return null;
    const item = items[0];

    // Carousel
    const carouselMedia = item.carousel_media as any[];
    if (carouselMedia && carouselMedia.length > 0) {
      const urls: string[] = [];
      for (const m of carouselMedia) {
        const videoVersions = m.video_versions as any[];
        if (videoVersions && videoVersions.length > 0) {
          urls.push(videoVersions[0].url);
          continue;
        }
        const candidates = deepGet(m, [
          'image_versions2',
          'candidates',
        ]) as any[];
        if (candidates && candidates.length > 0) {
          let best = candidates[0];
          let bestArea = best.width * best.height;
          for (const c of candidates) {
            const area = c.width * c.height;
            if (area > bestArea) {
              best = c;
              bestArea = area;
            }
          }
          urls.push(best.url);
        }
      }
      if (urls.length > 0) {
        return {
          id: shortcode,
          title: item.caption?.text,
          downloadUrl: '',
          mediaType: MediaType.images,
          imageUrls: urls,
          localImagePaths: [],
        };
      }
    }

    // Single video
    const videoVersions = item.video_versions as any[];
    if (videoVersions && videoVersions.length > 0) {
      return {
        id: shortcode,
        title: item.caption?.text,
        downloadUrl: videoVersions[0].url,
        mediaType: MediaType.video,
        imageUrls: [],
        localImagePaths: [],
      };
    }

    // Single image
    const candidates = deepGet(item, [
      'image_versions2',
      'candidates',
    ]) as any[];
    if (candidates && candidates.length > 0) {
      return {
        id: shortcode,
        title: item.caption?.text,
        downloadUrl: '',
        mediaType: MediaType.images,
        imageUrls: [candidates[0].url],
        localImagePaths: [],
      };
    }

    return null;
  }

  // ── X (Twitter) Local Parsing ──

  private async resolveXLocally(url: string): Promise<VideoInfo> {
    const cookies = await CookieStore.getCookies('x');
    if (!cookies.auth_token || !cookies.ct0) {
      throw new Error('X (Twitter) 需要配置 Cookie 才能使用');
    }

    const idMatch = url.match(/\/status\/(\d+)/);
    if (!idMatch) throw new Error('无法从输入中提取有效链接');
    const tweetId = idMatch[1];

    await this.ensureXMetadata(cookies);

    const cookieStr = Object.entries(cookies)
      .map(([k, v]) => `${k}=${v}`)
      .join('; ');

    const variables = JSON.stringify({
      tweetId,
      withCommunity: false,
      includePromotedContent: false,
      withVoice: false,
    });
    const features = JSON.stringify({
      creator_subscriptions_tweet_preview_api_enabled: true,
      premium_content_api_read_enabled: false,
      communities_web_enable_tweet_community_results_fetch: true,
      c9s_tweet_anatomy_moderator_badge_enabled: true,
      responsive_web_edit_tweet_api_enabled: true,
      graphql_is_translatable_rweb_tweet_is_translatable_enabled: true,
      view_counts_everywhere_api_enabled: true,
      longform_notetweets_consumption_enabled: true,
      responsive_web_twitter_article_tweet_consumption_enabled: true,
      tweet_awards_web_tipping_enabled: false,
      creator_subscriptions_quote_tweet_preview_enabled: false,
      freedom_of_speech_not_reach_fetch_enabled: true,
      standardized_nudges_misinfo: true,
      tweet_with_visibility_results_prefer_gql_limited_actions_policy_enabled:
        true,
      rweb_video_timestamps_enabled: true,
      longform_notetweets_rich_text_read_enabled: true,
      longform_notetweets_inline_media_enabled: true,
      responsive_web_enhance_cards_enabled: false,
      responsive_web_graphql_exclude_directive_enabled: true,
      verified_phone_label_enabled: false,
      responsive_web_graphql_skip_user_profile_image_extensions_enabled: false,
      responsive_web_graphql_timeline_navigation_enabled: true,
      tweetypie_unmention_optimization_enabled: true,
    });

    const queryUrl = `https://x.com/i/api/graphql/${this.cachedQueryId}/TweetResultByRestId?variables=${encodeURIComponent(variables)}&features=${encodeURIComponent(features)}`;

    const resp = await fetch(queryUrl, {
      headers: {
        'User-Agent': DESKTOP_UA,
        Authorization: `Bearer ${this.cachedBearerToken}`,
        'X-Csrf-Token': cookies.ct0,
        Cookie: cookieStr,
      },
    });

    if (!resp.ok) {
      throw new Error(`下载失败 (HTTP ${resp.status})`);
    }

    const json = await resp.json();
    return this.extractXMedia(json, tweetId);
  }

  private async ensureXMetadata(
    cookies: Record<string, string>,
  ): Promise<void> {
    if (
      this.cachedQueryId &&
      this.cachedBearerToken &&
      this.cacheTime &&
      Date.now() - this.cacheTime.getTime() < 30 * 60 * 1000
    ) {
      return;
    }

    const cookieStr = Object.entries(cookies)
      .map(([k, v]) => `${k}=${v}`)
      .join('; ');

    const pageResp = await fetch('https://x.com/i/flow/login', {
      headers: {'User-Agent': DESKTOP_UA, Cookie: cookieStr},
    });
    const pageHtml = await pageResp.text();

    const jsMatch = pageHtml.match(
      /https:\/\/abs\.twimg\.com\/responsive-web\/client-web[^"]*main\.[a-f0-9]+\.js/,
    );
    if (!jsMatch) throw new Error('无法获取 X 元数据');

    const jsResp = await fetch(jsMatch[0]);
    const jsContent = await jsResp.text();

    const queryIdMatch = jsContent.match(
      /queryId:"([A-Za-z0-9_-]{20,})"[^}]*operationName:"TweetResultByRestId"/,
    );
    const bearerMatch = jsContent.match(/"(AAAAAA[A-Za-z0-9%]+)"/);

    if (!queryIdMatch || !bearerMatch) {
      throw new Error('无法从 X 提取认证信息');
    }

    this.cachedQueryId = queryIdMatch[1];
    this.cachedBearerToken = bearerMatch[1];
    this.cacheTime = new Date();
  }

  private extractXMedia(json: any, tweetId: string): VideoInfo {
    const result = deepGet(json, ['data', 'tweetResult', 'result']);
    if (!result) throw new Error('解析失败：未找到视频数据');

    let tweetData = result;
    if (result.tweet) tweetData = result.tweet;

    const legacy = tweetData.legacy;
    const fullText = legacy?.full_text;
    const extMedia = deepGet(legacy, ['extended_entities', 'media']) as any[];
    if (!extMedia || extMedia.length === 0) {
      throw new Error('解析失败：未找到视频链接');
    }

    const videos: any[] = [];
    const photos: string[] = [];

    for (const m of extMedia) {
      const type = m.type;
      if (type === 'video' || type === 'animated_gif') {
        const variants = deepGet(m, ['video_info', 'variants']) as any[];
        if (variants) {
          const mp4s = variants
            .filter(
              (v: any) =>
                v.content_type === 'video/mp4' && v.bitrate != null,
            )
            .sort((a: any, b: any) => b.bitrate - a.bitrate);
          if (mp4s.length > 0) videos.push(mp4s[0]);
        }
      } else if (type === 'photo') {
        const photoUrl = m.media_url_https;
        if (photoUrl?.includes('pbs.twimg.com')) photos.push(photoUrl);
      }
    }

    if (videos.length > 0) {
      return {
        id: tweetId,
        title: fullText,
        downloadUrl: videos[0].url,
        mediaType: MediaType.video,
        imageUrls: [],
        localImagePaths: [],
      };
    }

    if (photos.length > 0) {
      return {
        id: tweetId,
        title: fullText,
        downloadUrl: '',
        mediaType: MediaType.images,
        imageUrls: photos,
        localImagePaths: [],
      };
    }

    throw new Error('解析失败：未找到视频链接');
  }

  // ── Xiaohongshu Local Parsing ──

  private async resolveXiaohongshuLocally(url: string): Promise<VideoInfo> {
    const result = await this.httpGetFollowRedirects(url);
    const {body: html, finalUrl} = result;

    const idMatch =
      finalUrl.match(/\/explore\/([a-f0-9]+)/) ||
      finalUrl.match(/\/discovery\/item\/([a-f0-9]+)/);
    const noteId = idMatch?.[1] ?? `xhs_${Date.now()}`;

    const jsonStr = extractBracketJson(html, 'window.__INITIAL_STATE__');
    if (jsonStr) {
      const cleaned = jsonStr.replace(/:\s*undefined/g, ': null');
      const json = JSON.parse(cleaned);

      const noteData =
        deepGet(json, ['noteData', 'data', 'noteData']) ??
        this.findNoteInMap(json);

      if (noteData && typeof noteData === 'object') {
        const type = noteData.type;
        const title = noteData.title;

        if (type === 'normal') {
          const imageList = noteData.imageList as any[];
          if (imageList) {
            const urls: string[] = [];
            for (const img of imageList) {
              const infoList = img.infoList as any[];
              if (infoList) {
                let bestUrl: string | null = null;
                for (const info of infoList) {
                  if (info.url) {
                    if (info.imageScene === 'H5_DTL') {
                      bestUrl = info.url;
                      break;
                    }
                    if (!bestUrl) bestUrl = info.url;
                  }
                }
                if (bestUrl) urls.push(bestUrl);
              }
            }
            if (urls.length > 0) {
              return {
                id: noteId,
                title,
                downloadUrl: '',
                mediaType: MediaType.images,
                imageUrls: urls,
                localImagePaths: [],
              };
            }
          }
        } else if (type === 'video') {
          const stream = deepGet(noteData, ['video', 'media', 'stream']);
          if (stream && typeof stream === 'object') {
            for (const codec of ['h264', 'h265', 'av1']) {
              const codecStreams = stream[codec] as any[];
              if (codecStreams && codecStreams.length > 0) {
                const masterUrl = codecStreams[0].masterUrl;
                if (masterUrl) {
                  return {
                    id: noteId,
                    title,
                    downloadUrl: masterUrl,
                    mediaType: MediaType.video,
                    imageUrls: [],
                    localImagePaths: [],
                  };
                }
              }
            }
          }
        }
      }
    }

    // Regex fallback
    const cdnMatch = html.match(/https?:\/\/[^\s"]*xhscdn[^\s"]*/);
    if (cdnMatch) {
      return {
        id: noteId,
        downloadUrl: cdnMatch[0],
        mediaType: MediaType.video,
        imageUrls: [],
        localImagePaths: [],
      };
    }

    throw new Error('解析失败：未找到视频链接');
  }

  private findNoteInMap(json: any): any {
    if (!json || typeof json !== 'object') return null;
    const noteDetailMap = json.note?.noteDetailMap;
    if (noteDetailMap && typeof noteDetailMap === 'object') {
      const values = Object.values(noteDetailMap) as any[];
      if (values.length > 0 && values[0]?.note) {
        return values[0].note;
      }
    }
    return null;
  }

  // ── Kuaishou Local Parsing ──

  private async resolveKuaishouLocally(url: string): Promise<VideoInfo> {
    const result = await this.httpGetFollowRedirects(url);
    const {body: html, finalUrl} = result;

    const idMatch =
      finalUrl.match(/\/short-video\/([A-Za-z0-9]+)/) ||
      finalUrl.match(/\/fw\/photo\/([A-Za-z0-9]+)/);
    const photoId = idMatch?.[1] ?? `ks_${Date.now()}`;

    // Try API first
    try {
      const apiResp = await fetch(
        'https://m.kuaishou.com/rest/wd/ugH5App/photo/simple/info',
        {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'User-Agent': MOBILE_UA,
            Referer: 'https://m.kuaishou.com/',
          },
          body: JSON.stringify({photoId, isLongVideo: false}),
        },
      );
      if (apiResp.ok) {
        const apiJson = await apiResp.json();
        const photo = apiJson.photo;
        if (photo) {
          const photoType = photo.photoType;
          if (
            photoType === 'VERTICAL_ATLAS' ||
            photoType === 'HORIZONTAL_ATLAS' ||
            photoType === 'MULTI_IMAGE'
          ) {
            const atlas = photo.atlas;
            if (atlas) {
              const cdnList = atlas.cdnList as any[];
              const list = atlas.list as string[];
              if (cdnList?.length > 0 && list?.length > 0) {
                const cdn = cdnList[0].cdn;
                const urls = list.map((item: string) => `https://${cdn}${item}`);
                return {
                  id: photoId,
                  title: photo.caption,
                  downloadUrl: '',
                  mediaType: MediaType.images,
                  imageUrls: urls,
                  localImagePaths: [],
                };
              }
            }
          }

          const mainMvUrls = photo.mainMvUrls as any[];
          if (mainMvUrls?.length > 0) {
            return {
              id: photoId,
              title: photo.caption,
              downloadUrl: mainMvUrls[0].url,
              mediaType: MediaType.video,
              imageUrls: [],
              localImagePaths: [],
            };
          }
        }
      }
    } catch {}

    // Try __APOLLO_STATE__
    const apolloStr = extractJSVariable(html, 'window.__APOLLO_STATE__');
    if (apolloStr) {
      const apolloJson = JSON.parse(apolloStr);
      for (const [key, val] of Object.entries(apolloJson) as [string, any][]) {
        if (
          key.includes('Photo') ||
          key.includes('Work') ||
          key.includes('Video')
        ) {
          if (val?.videoUrl) {
            return {
              id: photoId,
              downloadUrl: val.videoUrl,
              mediaType: MediaType.video,
              imageUrls: [],
              localImagePaths: [],
            };
          }
        }
      }
    }

    // Try __INITIAL_STATE__
    const initialStr = extractJSVariable(html, 'window.__INITIAL_STATE__');
    if (initialStr) {
      const initialJson = JSON.parse(initialStr);
      const videoUrl =
        findKey(initialJson, 'videoUrl') ??
        findKey(initialJson, 'video_url') ??
        findKey(initialJson, 'mp4Url');
      if (typeof videoUrl === 'string' && videoUrl) {
        return {
          id: photoId,
          downloadUrl: videoUrl,
          mediaType: MediaType.video,
          imageUrls: [],
          localImagePaths: [],
        };
      }
    }

    // Regex fallback
    const ksMatch = html.match(
      /https?:\/\/[^\s"]*(?:kwimgs|kwai\.net)[^\s"]*\.mp4[^\s"]*/,
    );
    if (ksMatch) {
      return {
        id: photoId,
        downloadUrl: ksMatch[0],
        mediaType: MediaType.video,
        imageUrls: [],
        localImagePaths: [],
      };
    }

    throw new Error('解析失败：未找到视频链接');
  }

  // ── Backend Resolution ──

  private async resolveViaBackend(text: string): Promise<VideoInfo> {
    const cookies = await CookieStore.allCookies();
    const body = JSON.stringify({text, cookies});

    let lastError: string | null = null;
    for (const backendUrl of BACKEND_URLS) {
      try {
        const controller = new AbortController();
        const timeoutId = setTimeout(() => controller.abort(), 30000);

        const resp = await fetch(backendUrl, {
          method: 'POST',
          headers: {'Content-Type': 'application/json'},
          body,
          signal: controller.signal,
        });

        clearTimeout(timeoutId);

        if (resp.ok) {
          const json: ResolveResponse = await resp.json();
          const backendBase = backendUrl.replace('/resolve', '');

          let downloadUrl = json.download_url ?? '';
          if (downloadUrl.startsWith('/')) {
            downloadUrl = `${backendBase}${downloadUrl}`;
          }
          downloadUrl = normalizeBackendUrl(downloadUrl, backendBase);

          const isImage = json.media_type === 'image';
          let imageUrls = json.image_urls ?? [];
          imageUrls = imageUrls.map((u: string) =>
            u.startsWith('/')
              ? `${backendBase}${u}`
              : normalizeBackendUrl(u, backendBase),
          );

          return {
            id: json.video_id ?? `backend_${Date.now()}`,
            title: json.title,
            downloadUrl,
            mediaType: isImage ? MediaType.images : MediaType.video,
            imageUrls,
            localImagePaths: [],
          };
        } else {
          try {
            const errJson = await resp.json();
            lastError = errJson.detail?.toString() ?? JSON.stringify(errJson);
          } catch {
            lastError = `HTTP ${resp.status}`;
          }
        }
      } catch (e: any) {
        lastError = e.message ?? String(e);
      }
    }

    throw new Error(`后端解析失败: ${lastError ?? '所有后端地址均不可用'}`);
  }

  // ── Download ──

  private async downloadFile(
    url: string,
    fileName: string,
    sourceUrl: string,
    onProgress?: ProgressCallback,
  ): Promise<string> {
    const downloadDir = `${RNFS.CachesDirectoryPath}/downloads`;
    await RNFS.mkdir(downloadDir);
    const filePath = `${downloadDir}/${fileName}`;

    const headers = buildDownloadHeaders(url, sourceUrl);

    const result = await RNFS.downloadFile({
      fromUrl: url,
      toFile: filePath,
      headers,
      progress: res => {
        if (res.contentLength > 0) {
          onProgress?.(res.bytesWritten / res.contentLength);
        }
      },
      progressInterval: 100,
    }).promise;

    if (result.statusCode !== 200 && result.statusCode !== 206) {
      throw new Error(`下载失败 (HTTP ${result.statusCode})`);
    }

    return filePath;
  }
}

// ── Utility Functions ──

function ensureHttps(url: string): string {
  if (url.startsWith('http://')) return url.replace('http://', 'https://');
  if (url.startsWith('//')) return `https:${url}`;
  return url;
}

function guessImageExt(url: string): string {
  const lower = url.toLowerCase();
  if (lower.includes('.png')) return 'png';
  if (lower.includes('.webp')) return 'webp';
  if (lower.includes('.gif')) return 'gif';
  return 'jpg';
}

function normalizeDouyinVideoUrl(url: string): string {
  let result = url.replace(/\/playwm\//g, '/play/');
  try {
    const parsed = new URL(result);
    parsed.searchParams.delete('watermark');
    parsed.searchParams.delete('logo_name');
    result = parsed.toString();
  } catch {}
  return result;
}

function normalizeBackendUrl(url: string, backendBase: string): string {
  try {
    const uri = new URL(url);
    if (
      uri.hostname === 'localhost' ||
      uri.hostname === '127.0.0.1' ||
      uri.hostname === '::1'
    ) {
      const backendUri = new URL(backendBase);
      uri.protocol = backendUri.protocol;
      uri.hostname = backendUri.hostname;
      uri.port = backendUri.port;
      return uri.toString();
    }
  } catch {}
  return url;
}

function extractJSVariable(html: string, varName: string): string | null {
  const pattern = new RegExp(varName.replace(/[.*+?^${}()|[\]\\]/g, '\\$&') + '\\s*=\\s*');
  const match = pattern.exec(html);
  if (!match) return null;
  return extractBalancedJson(html, match.index + match[0].length);
}

function extractBracketJson(html: string, varName: string): string | null {
  return extractJSVariable(html, varName);
}

function extractBalancedJson(html: string, start: number): string | null {
  if (start >= html.length) return null;
  const openChar = html[start];
  if (openChar !== '{' && openChar !== '[') return null;
  const closeChar = openChar === '{' ? '}' : ']';

  let depth = 0;
  let inString = false;
  let escape = false;

  for (let i = start; i < html.length; i++) {
    const c = html[i];

    if (escape) {
      escape = false;
      continue;
    }
    if (c === '\\' && inString) {
      escape = true;
      continue;
    }
    if (c === '"') {
      inString = !inString;
      continue;
    }
    if (inString) continue;

    if (c === openChar) depth++;
    else if (c === closeChar) {
      depth--;
      if (depth === 0) return html.substring(start, i + 1);
    }
  }
  return null;
}

function deepGet(obj: any, keys: string[]): any {
  let current = obj;
  for (const key of keys) {
    if (current && typeof current === 'object') {
      current = current[key];
    } else {
      return null;
    }
  }
  return current;
}

function findKey(obj: any, key: string, depth = 0): any {
  if (depth > 15) return null;
  if (obj && typeof obj === 'object') {
    if (!Array.isArray(obj) && key in obj) return obj[key];
    const values = Array.isArray(obj) ? obj : Object.values(obj);
    for (const value of values) {
      const result = findKey(value, key, depth + 1);
      if (result != null) return result;
    }
  }
  return null;
}

function buildDownloadHeaders(
  url: string,
  _sourceUrl: string,
): Record<string, string> {
  const headers: Record<string, string> = {'User-Agent': MOBILE_UA};

  try {
    const host = new URL(url).hostname;
    if (
      host.includes('instagram') ||
      host.includes('cdninstagram') ||
      host.includes('fbcdn')
    ) {
      headers.Referer = 'https://www.instagram.com/';
    } else if (
      host.includes('twimg') ||
      host.includes('x.com') ||
      host.includes('twitter')
    ) {
      headers.Referer = 'https://x.com/';
    } else if (
      host.includes('bilibili') ||
      host.includes('upos') ||
      host.includes('akamaized')
    ) {
      headers['User-Agent'] = DESKTOP_UA;
      headers.Referer = 'https://www.bilibili.com/';
    } else if (host.includes('xhscdn') || host.includes('xiaohongshu')) {
      headers.Referer = 'https://www.xiaohongshu.com/';
    } else if (
      host.includes('kwimgs') ||
      host.includes('kwai') ||
      host.includes('kuaishou') ||
      host.includes('yximgs')
    ) {
      headers.Referer = 'https://www.kuaishou.com/';
    }
  } catch {}

  return headers;
}

export const DownloadService = new DownloadServiceImpl();
