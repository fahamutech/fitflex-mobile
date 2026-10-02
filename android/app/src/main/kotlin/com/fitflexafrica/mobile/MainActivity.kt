package com.fitflexafrica.mobile

import android.app.NotificationChannel
import android.app.NotificationManager
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        createMessagesChannel()
    }

    // Pushes without a channel land in Android's low-key default one: no
    // pop-up, easy to miss. FitFlex messages get their own channel that
    // pops up and makes a sound (AndroidManifest names it as the default).
    // Creating a channel that already exists does nothing.
    private fun createMessagesChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val channel = NotificationChannel(
            "fitflex_messages",
            "Messages",
            NotificationManager.IMPORTANCE_HIGH,
        ).apply { description = "Messages from your gym and FitFlex" }
        getSystemService(NotificationManager::class.java)?.createNotificationChannel(channel)
    }
}
