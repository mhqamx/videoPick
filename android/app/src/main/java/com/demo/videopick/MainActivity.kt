package com.demo.videopick

import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.runtime.Composable
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import com.demo.videopick.ui.screen.CookieSettingsScreen
import com.demo.videopick.ui.screen.DownloadScreen
import com.demo.videopick.ui.theme.VideoPickTheme
import com.demo.videopick.viewmodel.DownloadViewModel

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()

        val sharedText = handleShareIntent(intent)

        setContent {
            VideoPickTheme {
                VideoPickApp(sharedText = sharedText)
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        // Handle share intent when activity is already running
        // For simplicity, we just set the intent
        setIntent(intent)
    }

    private fun handleShareIntent(intent: Intent?): String? {
        if (intent?.action == Intent.ACTION_SEND && intent.type == "text/plain") {
            return intent.getStringExtra(Intent.EXTRA_TEXT)
        }
        return null
    }
}

@Composable
fun VideoPickApp(sharedText: String? = null) {
    val navController = rememberNavController()
    val viewModel: DownloadViewModel = viewModel()

    // If shared text is provided, set it as input
    if (sharedText != null) {
        viewModel.updateInput(sharedText)
    }

    NavHost(navController = navController, startDestination = "download") {
        composable("download") {
            DownloadScreen(
                viewModel = viewModel,
                onNavigateToCookieSettings = {
                    navController.navigate("cookie_settings")
                },
            )
        }
        composable("cookie_settings") {
            CookieSettingsScreen(
                onBack = { navController.popBackStack() },
            )
        }
    }
}
