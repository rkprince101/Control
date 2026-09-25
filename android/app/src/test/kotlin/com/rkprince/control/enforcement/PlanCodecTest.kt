package com.rkprince.control.enforcement

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.json.JSONArray

/**
 * The plan is the only thing standing between a rule and an unblocked app, so
 * it has to survive the round trip through storage exactly.
 */
class PlanCodecTest {

    private val plan = Plan(
        blockedPackages = setOf("com.instagram.android", "com.android.chrome"),
        blockedDomains = setOf("instagram.com"),
        nextWakeAt = 1_700_000_000_000L,
        updatedAt = 1_699_999_000_000L,
        details = mapOf(
            "com.instagram.android" to BlockDetail(
                title = "Good night",
                status = "Unlocks at 8:00.",
                progressPercent = -1,
                unlockAt = 1_700_000_000_000L,
            ),
            "instagram.com" to BlockDetail(
                title = "Good night",
                status = "Finish 5,000 steps to unlock.",
                progressPercent = 64,
                unlockAt = 0L,
            ),
        ),
    )

    @Test
    fun `a plan survives encode and decode`() {
        val decoded = PlanCodec.decode(PlanCodec.encode(plan))

        assertEquals(plan.blockedPackages, decoded.blockedPackages)
        assertEquals(plan.blockedDomains, decoded.blockedDomains)
        assertEquals(plan.nextWakeAt, decoded.nextWakeAt)
        assertEquals(plan.updatedAt, decoded.updatedAt)
        assertEquals(plan.details, decoded.details)
    }

    @Test
    fun `removing an app from a plan removes it from the decoded plan`() {
        // The bug this guards: an app taken out of a block stayed blocked,
        // because the enforcer never re-read the plan.
        val shrunk = plan.copy(
            blockedPackages = plan.blockedPackages - "com.android.chrome",
        )
        val decoded = PlanCodec.decode(PlanCodec.encode(shrunk))

        assertTrue(decoded.blocks("com.instagram.android", now = 0L))
        assertTrue(!decoded.blocks("com.android.chrome", now = 0L))
    }

    @Test
    fun `a detail for an unknown key is empty rather than null`() {
        val decoded = PlanCodec.decode(PlanCodec.encode(plan))
        assertEquals(BlockDetail.EMPTY, decoded.detailFor("com.unknown.app", now = 0L))
    }

    @Test
    fun `an empty plan round trips`() {
        val decoded = PlanCodec.decode(PlanCodec.encode(Plan.EMPTY))
        assertEquals(Plan.EMPTY, decoded)
    }

    @Test
    fun `rules round trip with exclusions schedules and grants`() {
        val rules = listOf(NativeRule(
            id = "r", title = "Focus", mode = "time", apps = setOf("explicit.app"),
            categories = setOf("browsers", "games"), excludedApps = setOf("allowed.app"),
            blockedDomains = setOf("example.com"),
            schedule = listOf(NativeTimeRange(1320, 360, setOf(1, 7))),
            schedulePolarity = "allowDuring", blocked = true, allowedUntil = 12345L,
        ))
        val withRules = plan.copy(rules = rules)
        assertEquals(withRules, PlanCodec.decode(PlanCodec.encode(withRules)))
    }

    @Test
    fun `absent or null rules use legacy while empty rules are authoritative`() {
        val legacy = """{"packages":["old.app"],"domains":["example.com"]}"""
        assertEquals(null, PlanCodec.decode(legacy).rules)
        assertTrue(PlanCodec.decode(legacy).blocks("old.app", now = 0L))
        assertEquals(null, PlanCodec.decode("""{"rules":null}""").rules)
        val empty = PlanCodec.decode(PlanCodec.encode(plan.copy(rules = emptyList())))
        assertEquals(emptyList<NativeRule>(), empty.rules)
        assertTrue(!empty.blocks("com.android.chrome", now = 0L))
    }

    @Test
    fun `channel maps decode rules and nested schedules`() {
        val raw = listOf(mapOf(
            "id" to "r", "title" to "Focus", "mode" to "time",
            "categories" to listOf("browsers"), "excludedApps" to listOf("allowed.app"),
            "blocked" to false, "allowedUntil" to 0L, "schedulePolarity" to "allowDuring",
            "schedule" to listOf(mapOf("startMinute" to 60, "endMinute" to 120, "weekdays" to listOf(1, 7))),
        ))
        val rule = PlanCodec.decodeRules(JSONArray(raw)).single()
        assertEquals(setOf("allowed.app"), rule.excludedApps)
        assertEquals(listOf(NativeTimeRange(60, 120, setOf(1, 7))), rule.schedule)
        assertEquals("allowDuring", rule.schedulePolarity)
    }

    @Test(expected = IllegalArgumentException::class)
    fun `invalid schedule minutes reject the incoming rules`() {
        PlanCodec.decodeRules(JSONArray("""[{"id":"r","mode":"time","schedule":[{"startMinute":1440,"endMinute":0,"weekdays":[1]}]}]"""))
    }

    @Test
    fun `a stale plan is recognised, a future one is not`() {
        val now = 1_700_000_000_000L
        assertTrue(plan.copy(nextWakeAt = now - 1).isStale(now))
        assertTrue(!plan.copy(nextWakeAt = now + 1).isStale(now))
        // Nothing time-driven: never stale.
        assertTrue(!plan.copy(nextWakeAt = 0L).isStale(now))
    }
}
