package com.rkprince.control.surface

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class AlarmRestoreReceiverTest {
    @Test
    fun `clock, time zone and exact-alarm changes re-arm every alarm`() {
        assertTrue(AlarmRestoreReceiver.handles("android.intent.action.TIME_SET"))
        assertTrue(AlarmRestoreReceiver.handles("android.intent.action.TIMEZONE_CHANGED"))
        assertTrue(
            AlarmRestoreReceiver.handles(
                "android.app.action.SCHEDULE_EXACT_ALARM_PERMISSION_STATE_CHANGED",
            ),
        )
    }

    @Test
    fun `anything else is ignored`() {
        assertFalse(AlarmRestoreReceiver.handles(null))
        assertFalse(AlarmRestoreReceiver.handles("android.intent.action.SCREEN_ON"))
        assertFalse(AlarmRestoreReceiver.handles("android.intent.action.BOOT_COMPLETED"))
    }
}
