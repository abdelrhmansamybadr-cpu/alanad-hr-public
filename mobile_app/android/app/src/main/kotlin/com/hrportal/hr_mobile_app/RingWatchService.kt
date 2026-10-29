package com.hrportal.hr_mobile_app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.media.Ringtone
import android.media.RingtoneManager
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import android.os.VibrationEffect
import android.os.Vibrator
import org.json.JSONArray
import java.net.HttpURLConnection
import java.net.URL

/**
 * Keeps watching for a meeting that is ringing for the signed-in person, even when the app is closed or in the
 * background (there is no Firebase push behind the app). Every few seconds it asks the server the same question the
 * open app asks (`GET /meetings/ring`). When one is due and the app is not on screen it plays the phone ringtone,
 * vibrates and shows a full-screen "incoming meeting" notification with Decline / Join.
 *
 * Sign-in details are handed over by the app through [MainActivity] and kept in private preferences; signing out clears them.
 */
class RingWatchService : Service() {
    companion object {
        const val PREFS = "ringwatch"
        const val ACTION_DECLINE = "alanad.ring.DECLINE"
        const val EXTRA_ID = "meetingId"
        private const val WATCH_CH = "ring_watch_v1"
        private const val RING_CH = "meeting_ring_v1"
        private const val WATCH_ID = 7001
        private const val RING_ID = 7002
        private const val POLL_MS = 4000L
        private const val RING_MAX_MS = 45000L

        @Volatile var instance: RingWatchService? = null

        fun start(ctx: Context) {
            val i = Intent(ctx, RingWatchService::class.java)
            if (Build.VERSION.SDK_INT >= 26) ctx.startForegroundService(i) else ctx.startService(i)
        }

        fun stop(ctx: Context) {
            ctx.stopService(Intent(ctx, RingWatchService::class.java))
        }
    }

    @Volatile private var running = false
    private var worker: Thread? = null
    private var wake: PowerManager.WakeLock? = null
    private var ringtone: Ringtone? = null
    private var ringingId = -1
    private var ringStarted = 0L
    private val handled = HashSet<Int>()

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        instance = this
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= 26) {
            nm.createNotificationChannel(NotificationChannel(WATCH_CH, "Meeting calls", NotificationManager.IMPORTANCE_MIN).apply {
                description = "Lets the phone ring when a meeting you are invited to starts"
                setShowBadge(false)
            })
            nm.createNotificationChannel(NotificationChannel(RING_CH, "Incoming meeting", NotificationManager.IMPORTANCE_HIGH).apply {
                description = "Rings when a meeting you are invited to starts"
                setSound(null, null)
                enableVibration(false)
            })
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val watching: Notification = (if (Build.VERSION.SDK_INT >= 26) Notification.Builder(this, WATCH_CH) else Notification.Builder(this))
            .setSmallIcon(applicationInfo.icon)
            .setContentTitle("Al Anad HR")
            .setContentText("Ready for meeting calls")
            .setOngoing(true)
            .build()
        startForeground(WATCH_ID, watching)

        if (intent?.action == ACTION_DECLINE) {
            val id = intent.getIntExtra(EXTRA_ID, -1)
            if (id >= 0) Thread { decline(id) }.start()
        }
        if (!running) {
            running = true
            wake = (getSystemService(Context.POWER_SERVICE) as PowerManager).newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "alanad:ringwatch").apply { setReferenceCounted(false); acquire() }
            worker = Thread { loop() }.also { it.isDaemon = true; it.start() }
        }
        return START_STICKY
    }

    override fun onDestroy() {
        running = false
        stopRing()
        try { wake?.release() } catch (_: Exception) {}
        if (instance === this) instance = null
        super.onDestroy()
    }

    // --------------------------------------------------------------------------------------------- polling

    private fun loop() {
        while (running) {
            try { poll() } catch (_: Exception) { /* a missed check is fine, the next one comes soon */ }
            // a ring never lasts longer than 45 s; after that the person has missed it
            if (ringingId >= 0 && System.currentTimeMillis() - ringStarted > RING_MAX_MS) {
                handled.add(ringingId)
                stopRing()
            }
            try { Thread.sleep(POLL_MS) } catch (_: InterruptedException) {}
        }
    }

    private fun conn(path: String, method: String): HttpURLConnection? {
        val p = getSharedPreferences(PREFS, MODE_PRIVATE)
        val base = p.getString("base", null) ?: return null
        val token = p.getString("token", null) ?: return null
        val c = URL("$base/api$path").openConnection() as HttpURLConnection
        c.requestMethod = method
        c.connectTimeout = 8000
        c.readTimeout = 8000
        c.setRequestProperty("Accept", "application/json")
        c.setRequestProperty("Authorization", "Bearer $token")
        p.getString("appId", null)?.let { if (it.isNotEmpty()) c.setRequestProperty("X-App-Id", it) }
        if (method == "POST") { c.doOutput = true; c.setRequestProperty("Content-Type", "application/json"); c.outputStream.use { it.write("{}".toByteArray()) } }
        return c
    }

    private fun poll() {
        val p = getSharedPreferences(PREFS, MODE_PRIVATE)
        if (p.getString("token", null) == null) { stopSelf(); return }
        if (MainActivity.visible) { stopRing(); return } // the open app rings by itself
        val c = conn("/meetings/ring", "GET") ?: return
        try {
            val code = c.responseCode
            if (code == 401) { p.edit().remove("token").apply(); stopSelf(); return }
            if (code != 200) return
            val text = c.inputStream.bufferedReader().use { it.readText() }
            val arr = try { JSONArray(text) } catch (_: Exception) { org.json.JSONObject(text).optJSONArray("data") ?: JSONArray() }
            var fresh: org.json.JSONObject? = null
            for (i in 0 until arr.length()) {
                val m = arr.optJSONObject(i) ?: continue
                if (!handled.contains(m.optInt("id"))) { fresh = m; break }
            }
            if (fresh == null) { stopRing(); return }
            if (fresh.optInt("id") != ringingId) ring(fresh.optInt("id"), fresh.optString("title"), fresh.optString("hostName"))
        } finally { c.disconnect() }
    }

    private fun decline(id: Int) {
        handled.add(id)
        stopRing()
        try { conn("/meetings/$id/dismiss", "POST")?.let { it.responseCode; it.disconnect() } } catch (_: Exception) {}
    }

    // --------------------------------------------------------------------------------------------- ringing

    private fun ring(id: Int, title: String, host: String) {
        stopRing()
        ringingId = id
        ringStarted = System.currentTimeMillis()
        try {
            val r = RingtoneManager.getRingtone(applicationContext, RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE))
            r.audioAttributes = AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_NOTIFICATION_RINGTONE).setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION).build()
            if (Build.VERSION.SDK_INT >= 28) r.isLooping = true
            r.play()
            ringtone = r
        } catch (_: Exception) {}
        try {
            val v = getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
            val pattern = longArrayOf(0, 900, 700)
            if (Build.VERSION.SDK_INT >= 26) v.vibrate(VibrationEffect.createWaveform(pattern, 0)) else @Suppress("DEPRECATION") v.vibrate(pattern, 0)
        } catch (_: Exception) {}

        val open = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra("ring", true)
        }
        val immutable = if (Build.VERSION.SDK_INT >= 23) PendingIntent.FLAG_IMMUTABLE else 0
        val openPi = PendingIntent.getActivity(this, 1, open, PendingIntent.FLAG_UPDATE_CURRENT or immutable)
        val declinePi = PendingIntent.getService(this, 2, Intent(this, RingWatchService::class.java).setAction(ACTION_DECLINE).putExtra(EXTRA_ID, id), PendingIntent.FLAG_UPDATE_CURRENT or immutable)
        val b = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(this, RING_CH) else Notification.Builder(this)
        b.setSmallIcon(applicationInfo.icon)
            .setContentTitle("Incoming meeting")
            .setContentText(if (host.isNotEmpty()) "$title - $host" else title)
            .setCategory(Notification.CATEGORY_CALL)
            .setOngoing(true)
            .setAutoCancel(false)
            .setContentIntent(openPi)
            .setFullScreenIntent(openPi, true)
            .addAction(Notification.Action.Builder(null, "Decline", declinePi).build())
            .addAction(Notification.Action.Builder(null, "Join", openPi).build())
        if (Build.VERSION.SDK_INT < 26) @Suppress("DEPRECATION") b.setPriority(Notification.PRIORITY_MAX)
        (getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager).notify(RING_ID, b.build())
    }

    /** Stops the sound, the vibration and the call notification. Safe to call from any thread. */
    fun stopRing() {
        try { ringtone?.stop() } catch (_: Exception) {}
        ringtone = null
        try { (getSystemService(Context.VIBRATOR_SERVICE) as Vibrator).cancel() } catch (_: Exception) {}
        if (ringingId >= 0) {
            try { (getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager).cancel(RING_ID) } catch (_: Exception) {}
            ringingId = -1
        }
    }
}
