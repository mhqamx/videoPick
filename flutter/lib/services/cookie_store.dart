import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class PlatformCookieField {
  final String key;
  final String displayName;

  const PlatformCookieField({required this.key, required this.displayName});
}

class PlatformCookieConfig {
  final String platform;
  final String displayName;
  final List<PlatformCookieField> fields;
  final String footerText;

  const PlatformCookieConfig({
    required this.platform,
    required this.displayName,
    required this.fields,
    required this.footerText,
  });
}

class CookieStore {
  static const _prefsKey = 'platform_cookies';

  static const supportedPlatforms = [
    PlatformCookieConfig(
      platform: 'instagram',
      displayName: 'Instagram',
      fields: [
        PlatformCookieField(key: 'sessionid', displayName: 'sessionid'),
        PlatformCookieField(key: 'ds_user_id', displayName: 'ds_user_id'),
        PlatformCookieField(key: 'csrftoken', displayName: 'csrftoken'),
      ],
      footerText: '在浏览器登录 Instagram，从开发者工具 → Application → Cookies 中获取',
    ),
    PlatformCookieConfig(
      platform: 'x',
      displayName: 'X (Twitter)',
      fields: [
        PlatformCookieField(key: 'auth_token', displayName: 'auth_token'),
        PlatformCookieField(key: 'ct0', displayName: 'ct0'),
      ],
      footerText: '在浏览器登录 X，从开发者工具 → Application → Cookies 中获取',
    ),
  ];

  static Future<Map<String, Map<String, String>>> allCookies() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null) return {};
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return decoded.map((k, v) => MapEntry(
            k,
            (v as Map<String, dynamic>)
                .map((k2, v2) => MapEntry(k2, v2 as String)),
          ));
    } catch (_) {
      return {};
    }
  }

  static Future<Map<String, String>> getCookies(String platform) async {
    final all = await allCookies();
    return all[platform] ?? {};
  }

  static Future<void> saveCookies(
      String platform, Map<String, String> cookies) async {
    final all = await allCookies();
    final filtered = Map<String, String>.from(cookies)
      ..removeWhere((_, v) => v.trim().isEmpty);
    if (filtered.isEmpty) {
      all.remove(platform);
    } else {
      all[platform] = filtered;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, jsonEncode(all));
  }

  static Future<void> clearCookies(String platform) async {
    final all = await allCookies();
    all.remove(platform);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, jsonEncode(all));
  }

  static Future<bool> hasCookies(String platform) async {
    final cookies = await getCookies(platform);
    return cookies.isNotEmpty;
  }
}
