package com.rkprince.control.insights

import org.junit.Assert.assertEquals
import org.junit.Test

class StepDayTest {
    private val mon = 20261012
    private val tue = 20261013
    private val wed = 20261014

    private fun StepDay.read(raw: Long, day: Int, previous: Int, boot: Int = 4, bootedOnDay: Boolean = false) =
        record(raw, day, previous, boot, bootedOnDay)

    @Test fun `first reading on a phone booted today counts every step since boot`() {
        val state = StepDay().read(3200, tue, mon, bootedOnDay = true)
        assertEquals(3200L, state.stepsOn(tue))
    }

    @Test fun `first reading on a phone booted earlier starts from the reading`() {
        val state = StepDay().read(48_000, tue, mon)
        assertEquals(0L, state.stepsOn(tue))
        assertEquals(250L, state.read(48_250, tue, mon).stepsOn(tue))
    }

    @Test fun `steps walked before Control is opened still count`() {
        // The service heard 10,000 at 23:00 on Monday. Control is first opened
        // at noon on Tuesday at 15,500: Tuesday has 5,500, not zero.
        val monday = StepDay().read(9000, mon, 20261011).read(10_000, mon, 20261011)
        val tuesday = monday.read(15_500, tue, mon)
        assertEquals(5500L, tuesday.stepsOn(tue))
        assertEquals(0L, tuesday.stepsOn(mon), "yesterday is no longer reported")
    }

    @Test fun `a reading days old cannot be split and counting restarts`() {
        val monday = StepDay().read(10_000, mon, 20261011)
        val wednesday = monday.read(30_000, wed, tue)
        assertEquals(0L, wednesday.stepsOn(wed))
    }

    @Test fun `a reboot during the day banks what was counted before it`() {
        val before = StepDay().read(1000, tue, mon).read(3000, tue, mon)
        // Counter restarts after the reboot; boot count moves on.
        val after = before.read(400, tue, mon, boot = 5, bootedOnDay = true)
        assertEquals(2400L, after.stepsOn(tue))
        assertEquals(2600L, after.read(600, tue, mon, boot = 5).stepsOn(tue))
    }

    @Test fun `a reboot on a new day counts from the boot when it happened that day`() {
        val monday = StepDay().read(10_000, mon, 20261011)
        val tuesday = monday.read(800, tue, mon, boot = 5, bootedOnDay = true)
        assertEquals(800L, tuesday.stepsOn(tue))
    }

    @Test fun `a sensor reset without a reboot is treated as a restart`() {
        val before = StepDay().read(1000, tue, mon).read(2000, tue, mon)
        val after = before.read(50, tue, mon)
        assertEquals(1050L, after.stepsOn(tue))
    }

    @Test fun `a late event from yesterday moves where today began`() {
        // Last heard Monday at 10,000; Tuesday began on a reading of 10,300;
        // then a batched Monday-night event of 10,200 arrives.
        val tuesday = StepDay().read(10_000, mon, 20261011).read(10_300, tue, mon)
        assertEquals(300L, tuesday.stepsOn(tue))
        val corrected = tuesday.read(10_200, mon, 20261011)
        assertEquals(100L, corrected.stepsOn(tue))
    }

    @Test fun `a reading lower than the last is never counted as negative`() {
        val state = StepDay(day = tue, boot = 4, baseline = 500, banked = 0, lastSeen = 400)
        assertEquals(0L, state.stepsOn(tue))
    }

    @Test fun `negative readings are ignored`() {
        val state = StepDay().read(100, tue, mon, bootedOnDay = true)
        assertEquals(state, state.read(-1, tue, mon))
    }

    private fun assertEquals(expected: Long, actual: Long, message: String) =
        org.junit.Assert.assertEquals(message, expected, actual)
}
