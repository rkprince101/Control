package com.example.control.enforcement

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

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

        assertTrue(decoded.blocks("com.instagram.android"))
        assertTrue(!decoded.blocks("com.android.chrome"))
    }

    @Test
    fun `a detail for an unknown key is empty rather than null`() {
        val decoded = PlanCodec.decode(PlanCodec.encode(plan))
        assertEquals(BlockDetail.EMPTY, decoded.detailFor("com.unknown.app"))
    }

    @Test
    fun `an empty plan round trips`() {
        val decoded = PlanCodec.decode(PlanCodec.encode(Plan.EMPTY))
        assertEquals(Plan.EMPTY, decoded)
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
