package com.rkprince.control.enforcement

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class StepUnlockRulesTest {
    private val day = 86_400_000L
    private val dayOf: (Long) -> Int = { (it / day).toInt() }
    private val endOfDay: (Long) -> Long = { (it / day + 1) * day }

    private val now = 10 * day + 10 * 3_600_000L
    private val rule = NativeRule(
        id = "walk",
        title = "Walk first",
        mode = "condition",
        apps = setOf("video.app"),
        blocked = true,
        stepsTarget = 5000,
    )

    private fun mint(
        rules: List<NativeRule> = listOf(rule),
        grants: Map<String, NativeGrant> = emptyMap(),
        steps: Int,
        at: Long = now,
    ) = StepUnlockRules.mint(rules, grants, steps, at, dayOf, endOfDay)

    @Test fun `reaching the target mints an allowance until midnight`() {
        val grants = mint(steps = 5000)
        assertEquals(NativeGrant(now, endOfDay(now)), grants["walk"])
    }

    @Test fun `the rule's own allowance length is used when it has one`() {
        val grants = mint(listOf(rule.copy(unlockForMillis = 30 * 60_000L)), steps = 6000)
        assertEquals(now + 30 * 60_000L, grants["walk"]!!.expiresAt)
    }

    @Test fun `short of the target nothing is minted`() {
        assertTrue(mint(steps = 4999).isEmpty())
    }

    @Test fun `rules Dart did not gate on steps are left to Dart`() {
        assertTrue(mint(listOf(rule.copy(stepsTarget = 0)), steps = 99_999).isEmpty())
        assertTrue(mint(listOf(rule.copy(blocked = false)), steps = 99_999).isEmpty())
        assertTrue(mint(listOf(rule.copy(allowedUntil = now + 1)), steps = 99_999).isEmpty())
        assertTrue(mint(listOf(rule.copy(mode = "time")), steps = 99_999).isEmpty())
    }

    @Test fun `one allowance per rule per day, spent or not`() {
        val spent = mapOf("walk" to NativeGrant(now - 7_200_000L, now - 1_800_000L))
        assertEquals(spent, mint(grants = spent, steps = 20_000))
    }

    @Test fun `yesterday's spent allowance is dropped and today's can be earned`() {
        val yesterday = mapOf("walk" to NativeGrant(now - day, now - day + 60_000L))
        val grants = mint(grants = yesterday, steps = 5000)
        assertEquals(now, grants["walk"]!!.grantedAt)
    }

    @Test fun `allowances for deleted rules are dropped`() {
        val stale = mapOf("gone" to NativeGrant(now - 60_000L, now + 60_000L))
        assertFalse(mint(grants = stale, steps = 0).containsKey("gone"))
    }

    @Test fun `an allowance in force unblocks the rule and its end blocks it again`() {
        val grant = mint(steps = 5000)
        val plan = Plan(emptySet(), emptySet(), 0L, 0L, emptyMap(), rules = listOf(rule))
            .withNativeGrants(grant, 5000)
        assertFalse(plan.blocks("video.app", emptySet(), now + 1))
        assertTrue(plan.blocks("video.app", emptySet(), endOfDay(now)))
    }

    @Test fun `the block screen shows steps progress for a steps rule`() {
        val plan = Plan(emptySet(), emptySet(), 0L, 0L, emptyMap(), rules = listOf(rule))
            .withNativeGrants(emptyMap(), 1250)
        val detail = plan.detailFor("video.app", emptySet(), now)
        assertEquals(25, detail.progressPercent)
        assertTrue(detail.status, detail.status.contains("5"))
    }
}
