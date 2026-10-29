package com.hrportal.hr_mobile_app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/** After the phone restarts or the app is updated, start watching for meeting calls again if someone is signed in. */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        val signedIn = context.getSharedPreferences(RingWatchService.PREFS, Context.MODE_PRIVATE).getString("token", null) != null
        if (signedIn) try { RingWatchService.start(context) } catch (_: Exception) {}
    }
}
