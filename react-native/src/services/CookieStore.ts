import AsyncStorage from '@react-native-async-storage/async-storage';

export interface PlatformCookieField {
  key: string;
  displayName: string;
}

export interface PlatformCookieConfig {
  platform: string;
  displayName: string;
  fields: PlatformCookieField[];
  footerText: string;
}

const PREFS_KEY = 'platform_cookies';

export const supportedPlatforms: PlatformCookieConfig[] = [
  {
    platform: 'instagram',
    displayName: 'Instagram',
    fields: [
      {key: 'sessionid', displayName: 'sessionid'},
      {key: 'ds_user_id', displayName: 'ds_user_id'},
      {key: 'csrftoken', displayName: 'csrftoken'},
    ],
    footerText:
      '在浏览器登录 Instagram，从开发者工具 → Application → Cookies 中获取',
  },
  {
    platform: 'x',
    displayName: 'X (Twitter)',
    fields: [
      {key: 'auth_token', displayName: 'auth_token'},
      {key: 'ct0', displayName: 'ct0'},
    ],
    footerText:
      '在浏览器登录 X，从开发者工具 → Application → Cookies 中获取',
  },
];

export class CookieStore {
  static async allCookies(): Promise<Record<string, Record<string, string>>> {
    const raw = await AsyncStorage.getItem(PREFS_KEY);
    if (!raw) return {};
    try {
      return JSON.parse(raw);
    } catch {
      return {};
    }
  }

  static async getCookies(platform: string): Promise<Record<string, string>> {
    const all = await this.allCookies();
    return all[platform] ?? {};
  }

  static async saveCookies(
    platform: string,
    cookies: Record<string, string>,
  ): Promise<void> {
    const all = await this.allCookies();
    const filtered: Record<string, string> = {};
    for (const [k, v] of Object.entries(cookies)) {
      if (v.trim()) filtered[k] = v;
    }
    if (Object.keys(filtered).length === 0) {
      delete all[platform];
    } else {
      all[platform] = filtered;
    }
    await AsyncStorage.setItem(PREFS_KEY, JSON.stringify(all));
  }

  static async clearCookies(platform: string): Promise<void> {
    const all = await this.allCookies();
    delete all[platform];
    await AsyncStorage.setItem(PREFS_KEY, JSON.stringify(all));
  }

  static async hasCookies(platform: string): Promise<boolean> {
    const cookies = await this.getCookies(platform);
    return Object.keys(cookies).length > 0;
  }
}
