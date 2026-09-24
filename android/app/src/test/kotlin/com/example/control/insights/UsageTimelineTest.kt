package com.example.control.insights

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.util.TimeZone

class UsageTimelineTest {
    private val utc = TimeZone.getTimeZone("UTC")
    private val start = Instant.parse("2026-09-22T00:00:00Z").toEpochMilli()
    private fun at(minutes: Long) = start + minutes * 60_000
    private fun event(type: Int, minute: Long, pkg: String? = null) =
        UsageEventRecord(pkg, type, at(minute))

    private fun assertConsistent(value: UsageTimelineTotals) {
        assertEquals(value.perPackage.values.sum(), value.buckets.sumOf { it.millis })
        assertEquals(value.pickups, value.buckets.sumOf { it.pickups })
        assertTrue(value.buckets.all { it.millis in 0..(it.endMillis - it.startMillis) })
        value.buckets.zipWithNext().forEach { (before, after) ->
            assertEquals(before.endMillis, after.startMillis)
        }
    }

    @Test
    fun `midnight spill and ongoing session are clipped into distinct hours`() {
        val events = listOf(
            event(UsageMath.ACTIVITY_RESUMED, -30, "reader"),
            event(UsageMath.ACTIVITY_PAUSED, 30, "reader"),
            event(UsageMath.ACTIVITY_RESUMED, 70, "video"),
        )
        val value = UsageTimeline.accumulate(events, start, at(100), "hour", utc)
        assertEquals(listOf(30L * 60_000, 30L * 60_000), value.buckets.map { it.millis })
        assertEquals(at(100), value.buckets.last().endMillis)
        assertEquals(at(-30), value.firstEventAt)
        assertConsistent(value)
    }

    @Test
    fun `daily buckets split a session across midnight without duplicating totals`() {
        val events = listOf(
            event(UsageMath.ACTIVITY_RESUMED, 23 * 60 + 30, "reader"),
            event(UsageMath.SCREEN_INTERACTIVE, 23 * 60 + 31),
            event(UsageMath.KEYGUARD_HIDDEN, 23 * 60 + 32),
            event(UsageMath.SCREEN_INTERACTIVE, 24 * 60 + 1),
            event(UsageMath.KEYGUARD_HIDDEN, 24 * 60 + 2),
            event(UsageMath.ACTIVITY_PAUSED, 24 * 60 + 20, "reader"),
        )
        val daily = UsageTimeline.accumulate(events, start, at(26 * 60), "day", utc)
        val hourly = UsageTimeline.accumulate(events, start, at(26 * 60), "hour", utc)
        assertEquals(listOf(30L * 60_000, 20L * 60_000), daily.buckets.map { it.millis })
        assertEquals(daily.totalScreenMillis, hourly.totalScreenMillis)
        assertEquals(listOf(1, 1), daily.buckets.map { it.pickups })
        assertEquals(daily.pickups, hourly.pickups)
        assertConsistent(daily)
        assertConsistent(hourly)
    }

    @Test
    fun `null package screen and keyguard events close sessions and count pickups`() {
        val events = listOf(
            event(UsageMath.ACTIVITY_RESUMED, 0, "reader"),
            event(UsageMath.SCREEN_NON_INTERACTIVE, 10),
            event(UsageMath.SCREEN_INTERACTIVE, 20),
            event(UsageMath.KEYGUARD_HIDDEN, 21),
            event(UsageMath.ACTIVITY_RESUMED, 22, "reader"),
            event(UsageMath.KEYGUARD_SHOWN, 30),
        )
        val value = UsageTimeline.accumulate(events, start, at(120), "hour", utc)
        assertEquals(18L * 60_000, value.totalScreenMillis)
        assertEquals(listOf(1, 0), value.buckets.map { it.pickups })
        assertConsistent(value)
    }

    @Test
    fun `pickup source is chosen for whole window and respects exclusive end`() {
        val events = listOf(
            event(UsageMath.KEYGUARD_HIDDEN, -1),
            event(UsageMath.SCREEN_INTERACTIVE, 0),
            event(UsageMath.KEYGUARD_HIDDEN, 1),
            event(UsageMath.SCREEN_INTERACTIVE, 61),
            event(UsageMath.KEYGUARD_HIDDEN, 120),
            event(UsageMath.SCREEN_INTERACTIVE, 121),
        )
        for (bucket in listOf("hour", "day")) {
            val value = UsageTimeline.accumulate(events, start, at(120), bucket, utc)
            assertEquals(1, value.pickups)
            assertEquals(UsageMath.accumulate(events, start, at(120)).pickups, value.pickups)
            assertConsistent(value)
        }
        val wakes = UsageTimeline.accumulate(
            events.filter { it.type == UsageMath.SCREEN_INTERACTIVE }, start, at(120), "hour", utc,
        )
        assertEquals(listOf(1, 1), wakes.buckets.map { it.pickups })
    }

    @Test
    fun `empty history returns zero buckets without invented activity`() {
        val value = UsageTimeline.accumulate(emptyList(), start, at(150), "hour", utc)
        assertEquals(3, value.buckets.size)
        assertEquals(0L, value.totalScreenMillis)
        assertEquals(0, value.pickups)
        assertNull(value.firstEventAt)
        assertConsistent(value)
        assertTrue(UsageTimeline.accumulate(emptyList(), start, start, "day", utc).buckets.isEmpty())
    }

    @Test
    fun `partial first and last buckets clip both totals and pickups`() {
        val events = listOf(
            event(UsageMath.ACTIVITY_RESUMED, 0, "reader"),
            event(UsageMath.SCREEN_INTERACTIVE, 0),
            event(UsageMath.KEYGUARD_HIDDEN, 90),
            event(UsageMath.ACTIVITY_PAUSED, 120, "reader"),
        )
        val value = UsageTimeline.accumulate(events, at(15), at(90), "hour", utc)
        assertEquals(listOf(45L * 60_000, 30L * 60_000), value.buckets.map { it.millis })
        assertEquals(at(15), value.buckets.first().startMillis)
        assertEquals(0, value.pickups)
        assertConsistent(value)
    }

    @Test
    fun `excluded packages affect neither app totals nor bucket screen time`() {
        val events = listOf(
            event(UsageMath.ACTIVITY_RESUMED, 0, "reader"),
            event(UsageMath.ACTIVITY_RESUMED, 10, "system"),
            event(UsageMath.ACTIVITY_RESUMED, 20, "video"),
        )
        val value = UsageTimeline.accumulate(events, start, at(40), "hour", utc) { it != "system" }
        assertEquals(mapOf("reader" to 10L * 60_000, "video" to 20L * 60_000), value.perPackage)
        assertConsistent(value)
    }

    @Test
    fun `local DST days have 23 or 25 hourly buckets and one calendar day`() {
        val zone = ZoneId.of("America/New_York")
        for ((date, hours) in listOf("2026-03-08" to 23, "2026-11-01" to 25)) {
            val day = LocalDate.parse(date)
            val from = day.atStartOfDay(zone).toInstant().toEpochMilli()
            val until = day.plusDays(1).atStartOfDay(zone).toInstant().toEpochMilli()
            val events = listOf(UsageEventRecord("reader", UsageMath.ACTIVITY_RESUMED, from))
            val daily = UsageTimeline.accumulate(events, from, until, "day", TimeZone.getTimeZone(zone))
            val hourly = UsageTimeline.accumulate(events, from, until, "hour", TimeZone.getTimeZone(zone))
            assertEquals(hours, hourly.buckets.size)
            assertEquals(hours * 3_600_000L, daily.buckets.single().millis)
            assertEquals(daily.totalScreenMillis, hourly.totalScreenMillis)
            assertConsistent(daily)
            assertConsistent(hourly)
        }
    }

    @Test
    fun `partial repeated DST hour keeps its original offset`() {
        val zone = TimeZone.getTimeZone("America/New_York")
        val from = Instant.parse("2026-11-01T05:30:00Z").toEpochMilli()
        val until = Instant.parse("2026-11-01T07:30:00Z").toEpochMilli()
        val events = listOf(UsageEventRecord("reader", UsageMath.ACTIVITY_RESUMED, from))
        val value = UsageTimeline.accumulate(events, from, until, "hour", zone)
        assertEquals(listOf(1_800_000L, 3_600_000L, 1_800_000L), value.buckets.map { it.millis })
        assertConsistent(value)
    }

    @Test
    fun `midnight DST gap does not shift subsequent daily boundaries`() {
        val zone = ZoneId.of("America/Santiago")
        val day = LocalDate.parse("2026-09-06")
        val from = day.atStartOfDay(zone).toInstant().toEpochMilli()
        val until = day.plusDays(2).atStartOfDay(zone).toInstant().toEpochMilli()
        val events = listOf(UsageEventRecord("reader", UsageMath.ACTIVITY_RESUMED, from))
        val value = UsageTimeline.accumulate(events, from, until, "day", TimeZone.getTimeZone(zone))
        assertEquals(listOf(23 * 3_600_000L, 24 * 3_600_000L), value.buckets.map { it.millis })
        assertConsistent(value)
    }

    @Test
    fun `shutdown ends an open session rather than crediting powered off time`() {
        val events = listOf(
            event(UsageMath.ACTIVITY_RESUMED, 0, "reader"),
            event(UsageMath.DEVICE_SHUTDOWN, 10),
            event(UsageMath.DEVICE_STARTUP, 100),
        )
        val value = UsageTimeline.accumulate(events, start, at(120), "hour", utc)
        assertEquals(10L * 60_000, value.totalScreenMillis)
        assertConsistent(value)
    }
}
