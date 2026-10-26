package com.demo.videopick.channels

import android.annotation.SuppressLint
import android.graphics.Color
import android.os.Build
import android.os.Bundle
import android.view.ViewGroup
import android.webkit.*
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView
import androidx.activity.ComponentActivity
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.lifecycleScope
import androidx.lifecycle.repeatOnLifecycle
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsCompat
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull

/** A non-exported activity in a dedicated WebView process. Credentials never enter its result Intent. */
class YuanbaoLoginActivity : ComponentActivity() {
    private lateinit var webView: WebView
    private lateinit var status: TextView
    private lateinit var confirm: Button
    private var checking = false
    private var ready = false
    private var validated = false
    private var manualCheck: Job? = null
    private val service = WeChatChannelsService()

    companion object { private var profileConfigured = false }

    @SuppressLint("SetJavaScriptEnabled")
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (!profileConfigured) {
            if (Build.VERSION.SDK_INT >= 28) WebView.setDataDirectorySuffix("yuanbao_login")
            profileConfigured = true
        }
        setResult(RESULT_CANCELED)
        val root = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL; setBackgroundColor(Color.WHITE) }
        ViewCompat.setOnApplyWindowInsetsListener(root) { view, insets ->
            val bounds = insets.getInsets(WindowInsetsCompat.Type.systemBars() or WindowInsetsCompat.Type.ime())
            view.setPadding(bounds.left, bounds.top, bounds.right, bounds.bottom)
            insets
        }
        val toolbar = LinearLayout(this)
        toolbar.addView(Button(this).apply { text = "取消"; setOnClickListener { finish() } })
        toolbar.addView(TextView(this).apply { text = "登录元宝"; textSize = 20f; setTextColor(Color.BLACK) }, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f))
        toolbar.addView(Button(this).apply { text = "刷新"; setOnClickListener { webView.reload() } })
        root.addView(toolbar)
        root.addView(TextView(this).apply {
            text = "首次登录后即可直接下载视频号。请在元宝官方页面完成登录，可选择手机号登录。"
            textSize = 14f; setTextColor(Color.DKGRAY); setPadding(24, 16, 24, 16)
        })
        status = TextView(this).apply { setTextColor(Color.rgb(170, 80, 0)); setPadding(24, 0, 24, 8) }
        root.addView(status)
        webView = WebView(this).apply {
            settings.javaScriptEnabled = true
            settings.domStorageEnabled = true
            settings.allowFileAccess = false
            settings.allowContentAccess = false
            settings.mixedContentMode = WebSettings.MIXED_CONTENT_NEVER_ALLOW
            settings.userAgentString = WeChatChannelsService.USER_AGENT
            settings.useWideViewPort = true
            settings.loadWithOverviewMode = true
            settings.setSupportZoom(true)
            settings.builtInZoomControls = true
            settings.displayZoomControls = false
            // target=_blank stays within this browser; no JavaScript bridge is installed.
            settings.setSupportMultipleWindows(false)
            webViewClient = object : WebViewClient() {
                override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest): Boolean {
                    val url = request.url.toString().toHttpUrlOrNull() ?: return true
                    return url.scheme != "https" || listOf("tencent.com", "qq.com", "weixin.com").none { url.host == it || url.host.endsWith(".$it") }
                }
                override fun onReceivedError(view: WebView, request: WebResourceRequest, error: WebResourceError) {
                    if (request.isForMainFrame) status.text = "登录页面加载失败，请检查网络后点刷新。"
                }
            }
        }
        root.addView(webView, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, 0, 1f))
        confirm = Button(this).apply { text = "我已登录，继续"; setOnClickListener { manualCheck = lifecycleScope.launch { checkSession(true) } } }
        root.addView(confirm)
        setContentView(root)
        CookieManager.getInstance().apply {
            setAcceptCookie(true)
            setAcceptThirdPartyCookies(webView, true)
            // Never inject a stored session: explicit relogin must authenticate a fresh account.
            removeAllCookies {
                flush()
                WebStorage.getInstance().deleteAllData()
                if (!isFinishing && !isDestroyed) {
                    ready = true
                    webView.loadUrl(WeChatChannelsService.LOGIN_URL)
                }
            }
        }
        lifecycleScope.launch {
            repeatOnLifecycle(Lifecycle.State.STARTED) {
                while (!validated) { delay(3_000); checkSession(false) }
            }
        }
    }

    private suspend fun checkSession(showErrors: Boolean) {
        if (!ready || checking || validated || isFinishing) return
        checking = true; confirm.isEnabled = false
        try {
            val cookie = CookieManager.getInstance().getCookie(WeChatChannelsService.PARSE_URL).orEmpty()
            service.validateSession(cookie)
            if (isFinishing || !lifecycle.currentState.isAtLeast(Lifecycle.State.STARTED)) return
            YuanbaoSessionStore(this).save(cookie)
            validated = true
            setResult(RESULT_OK)
            finish()
        } catch (e: CancellationException) { throw e }
        catch (e: Exception) {
            if (showErrors) status.text = when (e) {
                is ChannelsLoginRequired -> "尚未检测到登录，请先在页面中完成登录。"
                is ChannelsException -> e.message
                else -> "确认登录失败，请稍后重试。"
            }
        } finally { checking = false; confirm.isEnabled = true }
    }

    override fun onStop() { manualCheck?.cancel(); super.onStop() }
    override fun onDestroy() {
        ready = false
        if (::webView.isInitialized) {
            webView.stopLoading(); webView.clearHistory(); webView.clearCache(true)
            (webView.parent as? ViewGroup)?.removeView(webView)
            webView.destroy()
            CookieManager.getInstance().removeAllCookies { CookieManager.getInstance().flush() }
            WebStorage.getInstance().deleteAllData()
        }
        super.onDestroy()
    }
}
