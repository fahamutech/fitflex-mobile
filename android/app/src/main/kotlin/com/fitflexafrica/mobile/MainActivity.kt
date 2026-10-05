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
    // Creating a channel that already exists only refreshes its name and
    // description, which follow the phone's language (res/values-sw).
    private fun createMessagesChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val channel = NotificationChannel(
            "fitflex_messages",
            getString(R.string.channel_messages_name),
            NotificationManager.IMPORTANCE_HIGH,
        ).apply { description = getString(R.string.channel_messages_description) }
        getSystemService(NotificationManager::class.java)?.createNotificationChannel(channel)
    }
}
