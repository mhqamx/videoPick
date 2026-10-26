package com.demo.videopick

import android.content.Intent
import android.app.Activity
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.activity.enableEdgeToEdge
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.platform.LocalContext
import com.demo.videopick.channels.YuanbaoLoginActivity
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import com.demo.videopick.data.model.SavedLocation
import com.demo.videopick.ui.screen.CookieSettingsScreen
import com.demo.videopick.ui.screen.DownloadScreen
import com.demo.videopick.ui.screen.LocationEditorScreen
import com.demo.videopick.ui.screen.LocationManagerScreen
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
    val state by viewModel.state.collectAsState()
    val context = LocalContext.current
    var loginLaunched by rememberSaveable { mutableStateOf(false) }
    val loginLauncher = rememberLauncherForActivityResult(ActivityResultContracts.StartActivityForResult()) {
        loginLaunched = false
        viewModel.yuanbaoLoginFinished(it.resultCode == Activity.RESULT_OK)
    }
    LaunchedEffect(state.showYuanbaoLogin) {
        if (state.showYuanbaoLogin && !loginLaunched) {
            loginLaunched = true
            loginLauncher.launch(Intent(context, YuanbaoLoginActivity::class.java))
        }
    }
    var editingLocation by remember { mutableStateOf<SavedLocation?>(null) }

    LaunchedEffect(sharedText) {
        if (sharedText != null) {
            viewModel.updateInput(sharedText)
            viewModel.startClipboardAutoDownloadIfNeeded(reason = "分享入口")
        }
    }

    // 前台切换时自动开启剪贴板雷达
    val lifecycleOwner = LocalLifecycleOwner.current
    DisposableEffect(lifecycleOwner) {
        val observer = LifecycleEventObserver { _, event ->
            if (event == Lifecycle.Event.ON_RESUME) {
                viewModel.startClipboardAutoDownloadIfNeeded(reason = "前台唤醒")
            }
        }
        lifecycleOwner.lifecycle.addObserver(observer)
        onDispose { lifecycleOwner.lifecycle.removeObserver(observer) }
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
                onYuanbaoLogin = viewModel::requestYuanbaoLogin,
                onBack = { navController.popBackStack() },
                onNavigateToLocationManager = {
                    navController.navigate("location_manager")
                },
            )
        }
        composable("location_manager") {
            LocationManagerScreen(
                onBack = { navController.popBackStack() },
                onEdit = { loc ->
                    editingLocation = loc
                    navController.navigate("location_editor")
                },
            )
        }
        composable("location_editor") {
            LocationEditorScreen(
                original = editingLocation,
                onBack = { navController.popBackStack() },
            )
        }
    }
}
