package com.rkprince.control.enforcement

import java.util.Calendar
import java.util.TimeZone
import org.junit.Assert.*
import org.junit.Test

class NativeRuleTest {
    private val browser = "example.browser"
    private val tokens = setOf("browsers", "all_apps")
    private val rule = NativeRule("r", "Focus", "condition", categories = setOf("browsers"), blocked = true)

    @Test fun `daytime includes start and excludes end on selected weekdays`() {
        val range = NativeTimeRange(600, 660, setOf(1))
        assertFalse(range.contains(599, 1))
        assertTrue(range.contains(600, 1))
        assertTrue(range.contains(659, 1))
        assertFalse(range.contains(660, 1))
        assertFalse(range.contains(600, 2))
    }

    @Test fun `overnight tail belongs to start weekday including Sunday wrap`() {
        val range = NativeTimeRange(1320, 360, setOf(7))
        assertFalse(range.contains(1319, 7))
        assertTrue(range.contains(1320, 7))
        assertTrue(range.contains(359, 1))
        assertFalse(range.contains(360, 1))
        assertFalse(range.contains(359, 7))
        assertFalse(range.contains(1320, 1))
    }

    @Test fun `equal endpoints cover 24 hours starting on selected day`() {
        val range = NativeTimeRange(600, 600, setOf(1))
        assertFalse(range.contains(599, 1))
        assertTrue(range.contains(600, 1))
        assertTrue(range.contains(599, 2))
        assertFalse(range.contains(600, 2))
        val midnight = NativeTimeRange(0, 0, setOf(1))
        assertTrue(midnight.contains(0, 1))
        assertTrue(midnight.contains(1439, 1))
        assertFalse(midnight.contains(0, 2))
    }

    @Test fun `local calendar ISO weekdays and polarity match Dart`() {
        val local = Calendar.getInstance(TimeZone.getTimeZone("GMT+05:30")).apply {
            clear()
            set(2026, Calendar.SEPTEMBER, 21, 10, 0) // Monday
        }
        val timed = rule.copy(mode = "time", schedule = listOf(NativeTimeRange(600, 660, setOf(1))), blocked = false)
        assertTrue(timed.isBlocked(local.timeInMillis, local))
        assertFalse(timed.copy(schedulePolarity = "allowDuring").isBlocked(local.timeInMillis, local))
        local.add(Calendar.HOUR_OF_DAY, 1)
        assertFalse(timed.isBlocked(local.timeInMillis, local))
        assertTrue(timed.copy(schedulePolarity = "allowDuring").isBlocked(local.timeInMillis, local))
        assertFalse(timed.copy(schedule = emptyList(), schedulePolarity = "allowDuring").isBlocked(local.timeInMillis, local))
    }

    @Test fun `condition expires exactly at grant boundary but zero keeps snapshot`() {
        val granted = rule.copy(blocked = false, allowedUntil = 1000L)
        assertFalse(granted.isBlocked(999L))
        assertTrue(granted.isBlocked(1000L))
        assertTrue(granted.isBlocked(1001L))
        assertFalse(granted.copy(allowedUntil = 0L).isBlocked(1001L))
        assertTrue(granted.copy(blocked = true).isBlocked(999L))
        for (mode in listOf("place", "device")) {
            assertFalse(granted.copy(mode = mode).isBlocked(1001L))
        }
    }

    @Test fun `exclusions apply only to category matches within their own rule`() {
        val excluded = rule.copy(excludedApps = setOf(browser))
        assertTrue(rule.targets(browser, tokens))
        assertFalse(excluded.targets(browser, tokens))
        assertTrue(excluded.copy(apps = setOf(browser)).targets(browser, tokens))
        assertTrue(Plan.EMPTY.copy(rules = listOf(excluded, rule)).blocks(browser, tokens, 1L))
        assertFalse(Plan.EMPTY.copy(rules = listOf(excluded)).blocks(browser, tokens, 1L))
    }

    @Test fun `authoritative rules replace stale flattened apps domains and details`() {
        val stale = Plan(setOf(browser), setOf("old.example"), 1, 1,
            mapOf(browser to BlockDetail("Old", "Old reason", 99, 2)))
        val fresh = stale.copy(rules = listOf(rule.copy(blocked = false)))
        assertFalse(fresh.blocks(browser, tokens, 1L))
        assertTrue(fresh.effectiveDomains(1L).isEmpty())
        assertEquals(BlockDetail.EMPTY, fresh.detailFor(browser, tokens, 1L))
        assertFalse(stale.copy(rules = emptyList()).blocks(browser, tokens, 1L))
        assertTrue(stale.blocks(browser, tokens, 1L))
    }

    @Test fun `new package candidates and grant expiry update effective unions and details`() {
        val plan = Plan.EMPTY.copy(rules = listOf(rule.copy(blocked = false, allowedUntil = 1000,
            blockedDomains = setOf("example.com"))))
        assertTrue(plan.effectivePackages(setOf(browser), { tokens }, 999L).isEmpty())
        assertEquals(setOf(browser), plan.effectivePackages(setOf(browser), { tokens }, 1000L))
        assertEquals(setOf("example.com"), plan.effectiveDomains(1000L))
        assertEquals("Focus", plan.detailFor(browser, tokens, 1000L).title)
        assertEquals("Focus", plan.detailFor("example.com", now = 1000L).title)
        assertEquals(0L, plan.detailFor(browser, tokens, 1000L).unlockAt)
    }
}
