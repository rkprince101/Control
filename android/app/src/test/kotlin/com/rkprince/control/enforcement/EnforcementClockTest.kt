package com.rkprince.control.enforcement

import java.util.Calendar
import java.util.TimeZone
import org.junit.Assert.*
import org.junit.Test

class EnforcementClockTest {
    private val epoch = 1_800_000_000_000L

    @Test fun `fresh clock advances with uptime including sleep not another wall sample`() {
        val clock = EnforcementTime(epoch, 1000L, 1)
        assertEquals(epoch, clock.now(1000L))
        assertEquals(epoch + 3_600_000L, clock.now(3_601_000L))
        assertEquals(epoch + 3_600_000L, clock.now(2000L))
    }

    @Test fun `same boot process restart ignores both forward and backward wall changes`() {
        val saved = ClockCheckpoint(epoch, 1000L, 7)
        for (wall in listOf(epoch - 86_400_000L, epoch + 86_400_000L)) {
            val restored = EnforcementTime(wall, 6000L, 7, saved)
            assertEquals(epoch + 5000L, restored.now(6000L))
            assertEquals(epoch + 6000L, restored.now(7000L))
        }
    }

    @Test fun `forward wall change cannot skip a blocking window in the same boot`() {
        val start = Calendar.getInstance(TimeZone.getTimeZone("UTC")).apply {
            clear()
            set(2026, Calendar.SEPTEMBER, 21, 10, 0)
        }.timeInMillis
        val saved = ClockCheckpoint(start, 1000L, 7)
        val clock = EnforcementTime(start + 3_600_000L, 2000L, 7, saved)
        val rule = NativeRule("r", "Focus", "time", schedule = listOf(NativeTimeRange(600, 660, setOf(1))))
        val now = clock.now(2000L)
        val local = Calendar.getInstance(TimeZone.getTimeZone("UTC")).apply { timeInMillis = now }
        assertTrue(rule.isBlocked(now, local))
    }

    @Test fun `condition grant expires on anchored elapsed time`() {
        val clock = EnforcementTime(epoch + 86_400_000L, 1000L, 7, ClockCheckpoint(epoch, 1000L, 7))
        val rule = NativeRule("r", "Focus", "condition", blocked = false, allowedUntil = epoch + 5000L)
        assertFalse(rule.isBlocked(clock.now(5999L)))
        assertTrue(rule.isBlocked(clock.now(6000L)))
    }

    @Test fun `new boot uses saved rollback floor even if uptime exceeds old uptime`() {
        val clock = EnforcementTime(epoch - 100_000L, 20_000L, 8, ClockCheckpoint(epoch, 1000L, 7))
        assertEquals(epoch, clock.now(20_000L))
        assertEquals(epoch + 1000L, clock.now(21_000L))
    }

    @Test fun `reboot must trust a forward wall clock without an external time source`() {
        val clock = EnforcementTime(epoch + 100_000L, 500L, 8, ClockCheckpoint(epoch, 1000L, 7))
        assertEquals(epoch + 100_000L, clock.now(500L))
    }

    @Test fun `unknown boot identity and inconsistent uptime use high water fallback`() {
        val unknown = EnforcementTime(epoch - 1000L, 2000L, -1, ClockCheckpoint(epoch, 1000L, -1))
        assertEquals(epoch, unknown.now(2000L))
        val inconsistent = EnforcementTime(epoch - 1000L, 500L, 7, ClockCheckpoint(epoch, 1000L, 7))
        assertEquals(epoch, inconsistent.now(500L))
    }

    @Test fun `checkpoint writes are immediate once then bounded to one minute`() {
        val clock = EnforcementTime(epoch, 1000L, 7)
        assertEquals(ClockCheckpoint(epoch, 1000L, 7), clock.checkpointIfDue(1000L))
        for (elapsed in 1000L..60_999L step 1000L) {
            clock.now(elapsed)
            assertNull(clock.checkpointIfDue(elapsed))
        }
        val saved = clock.checkpointIfDue(61_000L)
        assertEquals(ClockCheckpoint(epoch + 60_000L, 61_000L, 7), saved)
        val restored = EnforcementTime(epoch - 1000L, 62_000L, 7, saved)
        assertNull(restored.checkpointIfDue(62_000L))
        assertEquals(epoch + 61_000L, restored.now(62_000L))
    }

    @Test fun `schedules use current local timezone without changing enforcement epoch`() {
        val previous = TimeZone.getDefault()
        try {
            TimeZone.setDefault(TimeZone.getTimeZone("UTC"))
            val start = Calendar.getInstance().apply {
                clear()
                set(2026, Calendar.SEPTEMBER, 21, 10, 0)
            }.timeInMillis
            val clock = EnforcementTime(start, 1000L, 7)
            val rule = NativeRule("r", "Focus", "time", schedule = listOf(NativeTimeRange(600, 660, setOf(1))))
            assertTrue(rule.isBlocked(clock.now(1000L)))
            TimeZone.setDefault(TimeZone.getTimeZone("GMT+02:00"))
            assertEquals(start, clock.now(1000L))
            assertFalse(rule.isBlocked(clock.now(1000L)))
        } finally {
            TimeZone.setDefault(previous)
        }
    }

    @Test fun `monotonic epoch still follows local daylight saving boundaries`() {
        val start = Calendar.getInstance(TimeZone.getTimeZone("UTC")).apply {
            clear()
            set(2026, Calendar.MARCH, 8, 6, 59)
        }.timeInMillis
        val clock = EnforcementTime(start, 1000L, 7)
        val zone = TimeZone.getTimeZone("America/New_York")
        val rule = NativeRule("r", "Focus", "time", schedule = listOf(NativeTimeRange(180, 240, setOf(7))))
        val before = clock.now(1000L)
        val after = clock.now(121_000L)
        // 01:59 -> 03:01 locally, but only two real minutes elapse.
        assertFalse(rule.isBlocked(before, Calendar.getInstance(zone).apply { timeInMillis = before }))
        assertTrue(rule.isBlocked(after, Calendar.getInstance(zone).apply { timeInMillis = after }))
        assertEquals(120_000L, after - before)
    }
}
