package com.demo.videopick.ui.screen

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.dp
import com.demo.videopick.data.repository.CookieStore

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun CookieSettingsScreen(
    onBack: () -> Unit,
) {
    val context = LocalContext.current

    // Flat state map: "platform::fieldKey" -> value (nested MutableMap won't trigger recomposition)
    val cookieValues = remember {
        mutableStateMapOf<String, String>().apply {
            CookieStore.supportedPlatforms.forEach { config ->
                val saved = CookieStore.getCookies(context, config.platform)
                config.fields.forEach { field ->
                    put("${config.platform}::${field.key}", saved[field.key] ?: "")
                }
            }
        }
    }

    fun collectForPlatform(platform: String): Map<String, String> {
        val prefix = "$platform::"
        return cookieValues.filterKeys { it.startsWith(prefix) }
            .mapKeys { it.key.removePrefix(prefix) }
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Cookie 设置") },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, "返回")
                    }
                },
                actions = {
                    TextButton(onClick = {
                        // Save all
                        CookieStore.supportedPlatforms.forEach { config ->
                            CookieStore.saveCookies(context, config.platform, collectForPlatform(config.platform))
                        }
                        onBack()
                    }) {
                        Text("保存")
                    }
                },
            )
        },
    ) { padding ->
        LazyColumn(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .padding(horizontal = 16.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
            contentPadding = PaddingValues(vertical = 16.dp),
        ) {
            CookieStore.supportedPlatforms.forEach { config ->
                item(key = "${config.platform}_header") {
                    Text(
                        text = config.displayName,
                        style = MaterialTheme.typography.titleMedium,
                        color = MaterialTheme.colorScheme.primary,
                    )
                }

                items(config.fields, key = { "${config.platform}_${it.key}" }) { field ->
                    val stateKey = "${config.platform}::${field.key}"
                    OutlinedTextField(
                        value = cookieValues[stateKey] ?: "",
                        onValueChange = { newValue ->
                            cookieValues[stateKey] = newValue
                        },
                        label = { Text(field.label) },
                        placeholder = { Text(field.placeholder) },
                        modifier = Modifier.fillMaxWidth(),
                        singleLine = true,
                        textStyle = LocalTextStyle.current.copy(fontFamily = FontFamily.Monospace),
                    )
                }

                item(key = "${config.platform}_footer") {
                    Column {
                        Text(
                            text = CookieStore.footerText(config.platform),
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )

                        if (CookieStore.hasCookies(context, config.platform)) {
                            TextButton(
                                onClick = {
                                    CookieStore.clearCookies(context, config.platform)
                                    config.fields.forEach { field ->
                                        cookieValues["${config.platform}::${field.key}"] = ""
                                    }
                                },
                                colors = ButtonDefaults.textButtonColors(
                                    contentColor = MaterialTheme.colorScheme.error,
                                ),
                            ) {
                                Text("清除")
                            }
                        }

                        HorizontalDivider(modifier = Modifier.padding(top = 8.dp))
                    }
                }
            }
        }
    }
}
