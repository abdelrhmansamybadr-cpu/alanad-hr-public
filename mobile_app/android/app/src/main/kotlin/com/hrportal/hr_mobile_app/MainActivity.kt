package com.hrportal.hr_mobile_app

import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.media.Ringtone
import android.media.RingtoneManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.PowerManager
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        /** True while the app is on screen (the open app rings by itself, so the background watcher stays quiet). */
        @Volatile var visible = false
    }

    private var ringtone: Ringtone? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        showOverLockIfRing(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        showOverLockIfRing(intent)
    }

    /** Opened by the full-screen "incoming meeting" notification: show over the lock screen and wake the screen. */
    private fun showOverLockIfRing(i: Intent?) {
        if (i?.getBooleanExtra("ring", false) == true && Build.VERSION.SDK_INT >= 27) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
        }
    }

    override fun onResume() {
        super.onResume()
        visible = true
        RingWatchService.instance?.stopRing()
    }

    override fun onPause() {
        visible = false
        super.onPause()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Real phone ringtone for an incoming meeting while the app is open (Flutter's SystemSound.alert is silent on Android).
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "alanad/ring").setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> {
                    try {
                        if (ringtone == null) {
                            val uri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE)
                            val r = RingtoneManager.getRingtone(applicationContext, uri)
                            r.audioAttributes = AudioAttributes.Builder()
                                .setUsage(AudioAttributes.USAGE_NOTIFICATION_RINGTONE)
                                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                                .build()
                            if (Build.VERSION.SDK_INT >= 28) r.isLooping = true
                            ringtone = r
                        }
                        if (ringtone?.isPlaying != true) ringtone?.play()
                        result.success(true)
                    } catch (e: Exception) {
                        result.success(false)
                    }
                }
                "stop" -> {
                    try { ringtone?.stop() } catch (e: Exception) {}
                    ringtone = null
                    result.success(true)
                }
                // Signed in: keep watching for meeting calls even when the app is closed.
                "watch" -> {
                    try {
                        val a = call.arguments as? Map<*, *>
                        getSharedPreferences(RingWatchService.PREFS, Context.MODE_PRIVATE).edit()
                            .putString("base", a?.get("base") as? String)
                            .putString("token", a?.get("token") as? String)
                            .putString("appId", a?.get("appId") as? String)
                            .apply()
                        RingWatchService.start(applicationContext)
                        result.success(true)
                    } catch (e: Exception) {
                        result.success(false)
                    }
                }
                // Signed out: forget the sign-in and stop watching.
                "unwatch" -> {
                    getSharedPreferences(RingWatchService.PREFS, Context.MODE_PRIVATE).edit().remove("token").apply()
                    RingWatchService.stop(applicationContext)
                    result.success(true)
                }
                // Ask once to be left running in the background (Samsung and others otherwise put the app to sleep).
                "batteryExempt" -> {
                    try {
                        val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
                        if (!pm.isIgnoringBatteryOptimizations(packageName)) {
                            startActivity(Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS, Uri.parse("package:$packageName")))
                        }
                        result.success(true)
                    } catch (e: Exception) {
                        result.success(false)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onDestroy() {
        try { ringtone?.stop() } catch (e: Exception) {}
        super.onDestroy()
    }
}
