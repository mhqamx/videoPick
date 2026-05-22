package com.demo.videopick.location

import android.app.AppOpsManager
import android.content.Context
import android.os.Build
import android.os.Process
import android.provider.Settings

object MockLocationSelection {

    fun isSelected(context: Context): Boolean {
        val appOps = context.getSystemService(AppOpsManager::class.java)
        val appOpsMode = appOps?.let {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                it.unsafeCheckOpNoThrow(
                    AppOpsManager.OPSTR_MOCK_LOCATION,
                    Process.myUid(),
                    context.packageName,
                )
            } else {
                @Suppress("DEPRECATION")
                it.checkOpNoThrow(
                    AppOpsManager.OPSTR_MOCK_LOCATION,
                    Process.myUid(),
                    context.packageName,
                )
            }
        }
        val legacySetting = runCatching {
            Settings.Secure.getInt(context.contentResolver, "mock_location", 0)
        }.getOrDefault(0)
        return MockLocationSelectionEvaluator.isSelected(appOpsMode, legacySetting)
    }
}

internal object MockLocationSelectionEvaluator {

    fun isSelected(appOpsMode: Int?, legacySetting: Int): Boolean {
        return when (appOpsMode) {
            AppOpsManager.MODE_ALLOWED -> true
            AppOpsManager.MODE_DEFAULT, null -> legacySetting == 1
            else -> false
        }
    }
}
