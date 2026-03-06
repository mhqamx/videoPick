package com.demo.videopick.data.repository

import android.content.Context
import android.content.SharedPreferences
import kotlinx.serialization.json.Json
import kotlinx.serialization.encodeToString
import kotlinx.serialization.decodeFromString

data class PlatformCookieConfig(
    val platform: String,
    val displayName: String,
    val fields: List<CookieField>,
)

data class CookieField(
    val key: String,
    val label: String,
    val placeholder: String,
)

object CookieStore {
    private const val PREFS_NAME = "platform_cookies"
    private const val KEY = "cookies_json"

    val supportedPlatforms = listOf(
        PlatformCookieConfig(
            platform = "instagram",
            displayName = "Instagram",
            fields = listOf(
                CookieField("sessionid", "sessionid", "粘贴 sessionid 值"),
                CookieField("ds_user_id", "ds_user_id", "粘贴 ds_user_id 值"),
                CookieField("csrftoken", "csrftoken", "粘贴 csrftoken 值"),
            ),
        ),
        PlatformCookieConfig(
            platform = "x",
            displayName = "X (Twitter)",
            fields = listOf(
                CookieField("auth_token", "auth_token", "粘贴 auth_token 值"),
                CookieField("ct0", "ct0", "粘贴 ct0 值"),
            ),
        ),
    )

    private fun prefs(context: Context): SharedPreferences =
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    fun allCookies(context: Context): Map<String, Map<String, String>> {
        val raw = prefs(context).getString(KEY, null) ?: return emptyMap()
        return try {
            val all: Map<String, Map<String, String>> = Json.decodeFromString(raw)
            all.mapValues { (_, v) -> v.filterValues { it.isNotBlank() } }
                .filterValues { it.isNotEmpty() }
        } catch (_: Exception) {
            emptyMap()
        }
    }

    fun getCookies(context: Context, platform: String): Map<String, String> =
        allCookies(context)[platform] ?: emptyMap()

    fun saveCookies(context: Context, platform: String, cookies: Map<String, String>) {
        val all = allCookies(context).toMutableMap()
        val filtered = cookies.filterValues { it.isNotBlank() }
        if (filtered.isEmpty()) {
            all.remove(platform)
        } else {
            all[platform] = filtered
        }
        prefs(context).edit().putString(KEY, Json.encodeToString(all)).apply()
    }

    fun clearCookies(context: Context, platform: String) {
        val all = allCookies(context).toMutableMap()
        all.remove(platform)
        prefs(context).edit().putString(KEY, Json.encodeToString(all)).apply()
    }

    fun hasCookies(context: Context, platform: String): Boolean =
        getCookies(context, platform).isNotEmpty()

    fun footerText(platform: String): String = when (platform) {
        "instagram" -> "在浏览器登录 Instagram 后，使用 Cookie 导出插件获取 sessionid 等值"
        "x" -> "在浏览器登录 X/Twitter 后，使用 Cookie 导出插件获取 auth_token 和 ct0 值"
        else -> ""
    }
}
