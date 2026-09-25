package com.rkprince.control.insights

import org.junit.Assert.assertEquals
import org.junit.Test
import java.util.concurrent.TimeUnit

/**
 * Insights arithmetic.
 *
 * Every test here exists because of a real wrong number on screen: two separate
 * undercounts, and one spectacular overcount where several apps each claimed
 * the same two hours.
 */
class UsageMathTest {

    private val start = 1_700_000_000_000L
    private fun at(minutes: Long) = start + TimeUnit.MINUTES.toMillis(minutes)
    private fun minutes(millis: Long?) = TimeUnit.MILLISECONDS.toMinutes(millis ?: 0L)

    private fun resumed(pkg: String, minute: Long) =
        UsageEventRecord(pkg, UsageMath.ACTIVITY_RESUMED, at(minute))

    private fun paused(pkg: String, minute: Long) =
        UsageEventRecord(pkg, UsageMath.ACTIVITY_PAUSED, at(minute))

    private fun system(type: Int, minute: Long) =
        UsageEventRecord("android", type, at(minute))

    @Test
    fun `a simple session is credited to its own app`() {
        val totals = UsageMath.accumulate(
            listOf(resumed("chrome", 0), paused("chrome", 30)),
            start,
            at(60),
        )
        assertEquals(30L, minutes(totals.perPackage["chrome"]))
    }

    @Test
    fun `a missing pause does not credit every app the same hours`() {
        // The reported bug. Three apps opened, none of them emitted a pause,
        // and the user then sat in a fourth for two hours. Tracking a start
        // time per package independently credited all four with the full
        // window; only the app actually in front should get the time.
        val totals = UsageMath.accumulate(
            listOf(
                resumed("instagram", 0),
                resumed("youtube", 1),
                resumed("reddit", 2),
                resumed("control", 3),
            ),
            start,
            at(123),
        )

        assertEquals(1L, minutes(totals.perPackage["instagram"]))
        assertEquals(1L, minutes(totals.perPackage["youtube"]))
        assertEquals(1L, minutes(totals.perPackage["reddit"]))
        assertEquals(120L, minutes(totals.perPackage["control"]))
    }

    @Test
    fun `the total never exceeds the window`() {
        val totals = UsageMath.accumulate(
            listOf(
                resumed("a", 0),
                resumed("b", 10),
                resumed("c", 20),
                resumed("a", 30),
            ),
            start,
            at(40),
        )
        assertEquals(40L, minutes(totals.perPackage.values.sum()))
    }

    @Test
    fun `switching between activities in one app does not restart the clock`() {
        // A second resume for the same package, with no pause between, used to
        // overwrite the start time and throw away everything before it.
        val totals = UsageMath.accumulate(
            listOf(
                resumed("chrome", 0),
                resumed("chrome", 5),
                paused("chrome", 20),
            ),
            start,
            at(60),
        )
        assertEquals(20L, minutes(totals.perPackage["chrome"]))
    }

    @Test
    fun `locking the phone ends the session`() {
        // Otherwise an app left open when the screen goes off is credited until
        // the next event, which can be the following morning.
        val totals = UsageMath.accumulate(
            listOf(
                resumed("chrome", 0),
                system(UsageMath.SCREEN_NON_INTERACTIVE, 10),
            ),
            start,
            at(480),
        )
        assertEquals(10L, minutes(totals.perPackage["chrome"]))
    }

    @Test
    fun `a session running when the window opened is clipped to the window`() {
        // The query starts before midnight so the session is visible at all;
        // only the part inside the window counts.
        val totals = UsageMath.accumulate(
            listOf(
                UsageEventRecord("chrome", UsageMath.ACTIVITY_RESUMED, at(-30)),
                paused("chrome", 30),
            ),
            start,
            at(60),
        )
        assertEquals(30L, minutes(totals.perPackage["chrome"]))
    }

    @Test
    fun `an app still in the foreground is credited up to now`() {
        val totals = UsageMath.accumulate(
            listOf(resumed("chrome", 0)),
            start,
            at(45),
        )
        assertEquals(45L, minutes(totals.perPackage["chrome"]))
    }

    @Test
    fun `pickups prefer keyguard unlocks and fall back to screen wakes`() {
        val withKeyguard = UsageMath.accumulate(
            listOf(
                system(UsageMath.KEYGUARD_HIDDEN, 1),
                system(UsageMath.KEYGUARD_HIDDEN, 2),
                system(UsageMath.SCREEN_INTERACTIVE, 1),
            ),
            start,
            at(60),
        )
        assertEquals(2, withKeyguard.pickups)

        // No lock screen on this device, so keyguard events never arrive.
        val withoutKeyguard = UsageMath.accumulate(
            listOf(
                system(UsageMath.SCREEN_INTERACTIVE, 1),
                system(UsageMath.SCREEN_INTERACTIVE, 5),
                system(UsageMath.SCREEN_INTERACTIVE, 9),
            ),
            start,
            at(60),
        )
        assertEquals(3, withoutKeyguard.pickups)
    }

    @Test
    fun `events before the window do not count as pickups`() {
        val totals = UsageMath.accumulate(
            listOf(
                UsageEventRecord("android", UsageMath.KEYGUARD_HIDDEN, at(-10)),
                system(UsageMath.KEYGUARD_HIDDEN, 5),
            ),
            start,
            at(60),
        )
        assertEquals(1, totals.pickups)
    }
}
