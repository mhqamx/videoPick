package com.demo.videopick.channels

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.AtomicFile
import java.io.File
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/** Separate from CookieStore: no plaintext preferences, backups, or backend cookie map. */
class YuanbaoSessionStore(context: Context) {
    private val file = AtomicFile(File(context.noBackupFilesDir, "yuanbao_session.enc"))
    private val alias = context.packageName + ".yuanbao.session"

    fun cookieHeader(): String = runCatching {
        val data = file.readFully()
        require(data.size > 28)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.DECRYPT_MODE, key(create = false), GCMParameterSpec(128, data.copyOfRange(0, 12)))
        cipher.updateAAD(alias.toByteArray(Charsets.UTF_8))
        String(cipher.doFinal(data.copyOfRange(12, data.size)), Charsets.UTF_8)
            .takeIf(WeChatChannelsParser::validCookie).orEmpty()
    }.getOrDefault("")

    fun hasSession() = cookieHeader().isNotEmpty()

    fun save(cookie: String) {
        if (!WeChatChannelsParser.validCookie(cookie)) throw ChannelsLoginRequired()
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, key(create = true))
        cipher.updateAAD(alias.toByteArray(Charsets.UTF_8))
        val encrypted = cipher.iv + cipher.doFinal(cookie.toByteArray(Charsets.UTF_8))
        val stream = file.startWrite()
        try { stream.write(encrypted); file.finishWrite(stream) }
        catch (error: Exception) { file.failWrite(stream); throw ChannelsException("无法保存登录状态，请重试") }
    }

    fun clear() {
        file.delete()
        if (file.baseFile.exists()) throw ChannelsException("无法清除登录状态，请重试")
    }

    private fun key(create: Boolean): SecretKey {
        val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (store.getKey(alias, null) as? SecretKey)?.let { return it }
        if (!create) throw ChannelsLoginRequired()
        return KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore").apply {
            init(KeyGenParameterSpec.Builder(alias, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM).setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(256).build())
        }.generateKey()
    }
}
