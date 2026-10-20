package com.fitflexafrica.mobile

import android.net.ConnectivityManager
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class DeviceDataRulesTest {
    @Test
    fun belowAndroid7FailsClosed() {
        assertTrue(DeviceDataRules.dataSaverOn(23, null))
        assertTrue(
            DeviceDataRules.dataSaverOn(
                23,
                ConnectivityManager.RESTRICT_BACKGROUND_STATUS_DISABLED,
            ),
        )
    }

    @Test
    fun unknownStatusFailsClosed() {
        assertTrue(DeviceDataRules.dataSaverOn(34, null))
    }

    @Test
    fun dataSaverOnBlocksUnlessExempted() {
        assertTrue(
            DeviceDataRules.dataSaverOn(
                34,
                ConnectivityManager.RESTRICT_BACKGROUND_STATUS_ENABLED,
            ),
        )
        assertFalse(
            DeviceDataRules.dataSaverOn(
                34,
                ConnectivityManager.RESTRICT_BACKGROUND_STATUS_WHITELISTED,
            ),
        )
        assertFalse(
            DeviceDataRules.dataSaverOn(
                24,
                ConnectivityManager.RESTRICT_BACKGROUND_STATUS_DISABLED,
            ),
        )
    }
}
