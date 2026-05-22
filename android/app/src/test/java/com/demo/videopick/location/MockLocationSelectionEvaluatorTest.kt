package com.demo.videopick.location

import android.app.AppOpsManager
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class MockLocationSelectionEvaluatorTest {

    @Test
    fun `returns true when app ops allows mock location`() {
        assertTrue(
            MockLocationSelectionEvaluator.isSelected(
                appOpsMode = AppOpsManager.MODE_ALLOWED,
                legacySetting = 0,
            )
        )
    }

    @Test
    fun `returns false when app ops denies mock location even if legacy flag looks enabled`() {
        assertFalse(
            MockLocationSelectionEvaluator.isSelected(
                appOpsMode = AppOpsManager.MODE_IGNORED,
                legacySetting = 1,
            )
        )
    }

    @Test
    fun `falls back to legacy flag when app ops mode is unavailable`() {
        assertTrue(MockLocationSelectionEvaluator.isSelected(appOpsMode = null, legacySetting = 1))
        assertFalse(MockLocationSelectionEvaluator.isSelected(appOpsMode = null, legacySetting = 0))
    }
}
