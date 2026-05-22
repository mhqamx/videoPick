package com.demo.videopick.service

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.location.Location
import android.location.LocationManager
import android.location.provider.ProviderProperties
import android.os.Build
import android.os.IBinder
import android.os.SystemClock
import android.util.Log
import androidx.core.app.NotificationCompat
import com.demo.videopick.MainActivity
import com.demo.videopick.R
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/**
 * 通过 LocationManager.setTestProviderLocation 持续推送伪造坐标。
 * 前置：用户必须在「设置 → 开发者选项 → 选择模拟位置应用」里选中本 app。
 */
class MockLocationService : Service() {

    private var scope: CoroutineScope? = null
    private var pushJob: Job? = null
    private val providers = listOf(
        LocationManager.GPS_PROVIDER,
        LocationManager.NETWORK_PROVIDER,
    )

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        try {
            when (intent?.action) {
                ACTION_STOP -> { stopMocking(); stopSelf(); return START_NOT_STICKY }
                else -> {
                    val name = intent?.getStringExtra(EXTRA_NAME) ?: "未知位置"
                    val lat = intent?.getDoubleExtra(EXTRA_LAT, 0.0) ?: 0.0
                    val lng = intent?.getDoubleExtra(EXTRA_LNG, 0.0) ?: 0.0
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                        startForeground(
                            NOTIFICATION_ID,
                            buildNotification(name, lat, lng),
                            android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_LOCATION,
                        )
                    } else {
                        startForeground(NOTIFICATION_ID, buildNotification(name, lat, lng))
                    }
                    startMocking(lat, lng)
                }
            }
        } catch (e: Throwable) {
            Log.e(TAG, "Service 启动失败", e)
            IS_RUNNING = false
            stopSelf()
        }
        return START_STICKY
    }

    override fun onDestroy() {
        stopMocking()
        super.onDestroy()
    }

    private fun startMocking(lat: Double, lng: Double) {
        val lm = getSystemService(Context.LOCATION_SERVICE) as LocationManager
        for (p in providers) {
            try {
                if (lm.getProvider(p) != null) {
                    runCatching { lm.removeTestProvider(p) }
                }
                addTestProvider(lm, p)
                lm.setTestProviderEnabled(p, true)
            } catch (e: SecurityException) {
                Log.e(TAG, "addTestProvider 失败：未在开发者选项中选中本 app 为模拟位置 app", e)
                IS_RUNNING = false
                stopSelf()
                return
            } catch (e: Exception) {
                Log.e(TAG, "init provider $p 失败", e)
            }
        }
        IS_RUNNING = true
        CURRENT_LAT = lat; CURRENT_LNG = lng

        scope = CoroutineScope(Dispatchers.Default)
        pushJob = scope!!.launch {
            while (true) {
                pushOnce(lm, lat, lng)
                delay(1000L)
            }
        }
    }

    private fun pushOnce(lm: LocationManager, lat: Double, lng: Double) {
        for (p in providers) {
            try {
                val loc = Location(p).apply {
                    latitude = lat
                    longitude = lng
                    altitude = 30.0
                    accuracy = 1.0f
                    time = System.currentTimeMillis()
                    elapsedRealtimeNanos = SystemClock.elapsedRealtimeNanos()
                    bearing = 0.0f
                    speed = 0.0f
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        bearingAccuracyDegrees = 0.1f
                        verticalAccuracyMeters = 0.1f
                        speedAccuracyMetersPerSecond = 0.01f
                    }
                }
                lm.setTestProviderLocation(p, loc)
            } catch (e: Exception) {
                Log.w(TAG, "push $p 失败：${e.message}")
            }
        }
    }

    private fun addTestProvider(lm: LocationManager, provider: String) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            lm.addTestProvider(
                provider,
                ProviderProperties.Builder()
                    .setHasNetworkRequirement(false)
                    .setHasSatelliteRequirement(false)
                    .setHasCellRequirement(false)
                    .setPowerUsage(ProviderProperties.POWER_USAGE_LOW)
                    .setAccuracy(ProviderProperties.ACCURACY_FINE)
                    .build()
            )
        } else {
            @Suppress("DEPRECATION")
            lm.addTestProvider(
                provider,
                false, false, false, false, true, true, true,
                0, 1
            )
        }
    }

    private fun stopMocking() {
        pushJob?.cancel(); pushJob = null
        scope = null
        val lm = getSystemService(Context.LOCATION_SERVICE) as LocationManager
        for (p in providers) {
            runCatching { lm.setTestProviderEnabled(p, false) }
            runCatching { lm.removeTestProvider(p) }
        }
        IS_RUNNING = false
    }

    private fun buildNotification(name: String, lat: Double, lng: Double): Notification {
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val ch = NotificationChannel(CHANNEL_ID, "模拟定位", NotificationManager.IMPORTANCE_LOW)
                .apply { setShowBadge(false) }
            nm.createNotificationChannel(ch)
        }
        val tap = PendingIntent.getActivity(
            this, 0,
            Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val stop = PendingIntent.getService(
            this, 1,
            Intent(this, MockLocationService::class.java).apply { action = ACTION_STOP },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.drawable.app_icon)
            .setContentTitle("正在模拟定位：$name")
            .setContentText("%.6f, %.6f".format(lat, lng))
            .setOngoing(true)
            .setContentIntent(tap)
            .addAction(0, "停止", stop)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .build()
    }

    companion object {
        private const val TAG = "MockLocationService"
        private const val CHANNEL_ID = "mock_location"
        private const val NOTIFICATION_ID = 4711

        const val ACTION_STOP = "com.demo.videopick.action.STOP_MOCK"
        const val EXTRA_NAME = "name"
        const val EXTRA_LAT = "lat"
        const val EXTRA_LNG = "lng"

        @Volatile var IS_RUNNING: Boolean = false
            private set
        @Volatile var CURRENT_LAT: Double = 0.0
            private set
        @Volatile var CURRENT_LNG: Double = 0.0
            private set

        fun start(context: Context, name: String, lat: Double, lng: Double) {
            val intent = Intent(context, MockLocationService::class.java).apply {
                putExtra(EXTRA_NAME, name)
                putExtra(EXTRA_LAT, lat)
                putExtra(EXTRA_LNG, lng)
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun stop(context: Context) {
            val intent = Intent(context, MockLocationService::class.java).apply { action = ACTION_STOP }
            context.startService(intent)
        }
    }
}
