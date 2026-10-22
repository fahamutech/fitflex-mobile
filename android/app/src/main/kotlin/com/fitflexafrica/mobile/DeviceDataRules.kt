package com.fitflexafrica.mobile

import android.net.ConnectivityManager

// App photos (HERO_IMAGES_REMOTE): when the phone says to save data. Kept
// apart from MainActivity, with plain values in and out, so it has a JVM unit
// test (src/test).
object DeviceDataRules {
    private const val API_N = 24 // Build.VERSION_CODES.N

    // True means "do not download". Data Saver and its status only exist
    // from Android 7.0 (API 24); below that the app cannot tell, so it fails
    // closed and downloads nothing (bundled photos only). The app's minSdk is
    // 23, so this is Android 6.0 only. An unknown status also counts as on.
    // On with this app exempted (WHITELISTED) or off (DISABLED): downloads
    // are allowed.
    fun dataSaverOn(sdkInt: Int, restrictBackgroundStatus: Int?): Boolean {
        if (sdkInt < API_N) return true
        if (restrictBackgroundStatus == null) return true
        return restrictBackgroundStatus == ConnectivityManager.RESTRICT_BACKGROUND_STATUS_ENABLED
    }
}
