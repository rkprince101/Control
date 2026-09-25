package com.rkprince.control.enforcement

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.Assert.assertEquals
import com.rkprince.control.insights.AppCategoryRules

class BootReceiverTest {
    @Test
    fun `direct boot keeps system and emergency roles accessible`() {
        assertFalse(AppCategoryRules.canBlockBeforeUnlock(systemApp = true, essential = false))
        assertFalse(AppCategoryRules.canBlockBeforeUnlock(systemApp = false, essential = true))
        assertFalse(AppCategoryRules.canBlockBeforeUnlock(systemApp = true, essential = true))
        assertTrue(AppCategoryRules.canBlockBeforeUnlock(systemApp = false, essential = false))
    }

    @Test
    fun `unlock migration raises provisional clock to the persisted plan floor`() {
        val restored = EnforcementTime(
            wallMillis = 100L, elapsedMillis = 200L, bootCount = 3,
            saved = ClockCheckpoint(epochMillis = 100L, elapsedMillis = 100L, bootCount = 3),
            minimumEpochMillis = 10_000L,
        )
        assertEquals(10_000L, restored.now(200L))
        assertEquals(10_001L, restored.now(201L))
        assertEquals(10_001L, restored.checkpointIfDue(201L)!!.epochMillis)
    }

    @Test
    fun `unlock migration does not trust an edited wall clock again`() {
        val live = EnforcementTime(wallMillis = 1_000L, elapsedMillis = 100L, bootCount = 3)
        for (editedWall in listOf(10L, 100_000L)) {
            val restored = EnforcementTime(
                wallMillis = editedWall, elapsedMillis = 200L, bootCount = 3,
                saved = ClockCheckpoint(epochMillis = 900L, elapsedMillis = 500L, bootCount = 2),
                minimumEpochMillis = 950L,
                liveEpochMillis = live.now(200L),
            )
            assertEquals(1_100L, restored.now(200L))
            assertEquals(1_110L, restored.now(210L))
        }
    }

    @Test
    fun `recovery runs at locked boot unlocked boot and application update`() {
        assertTrue(BootReceiver.handles("android.intent.action.LOCKED_BOOT_COMPLETED"))
        assertTrue(BootReceiver.handles("android.intent.action.BOOT_COMPLETED"))
        assertTrue(BootReceiver.handles("android.intent.action.MY_PACKAGE_REPLACED"))
    }

    @Test
    fun `unrelated broadcasts cannot request recovery`() {
        assertFalse(BootReceiver.handles(null))
        assertFalse(BootReceiver.handles("android.intent.action.SCREEN_ON"))
        assertFalse(BootReceiver.handles("android.intent.action.PACKAGE_ADDED"))
    }

    @Test
    fun `persisted category rules enforce an expired reward without Flutter`() {
        val saved = Plan.EMPTY.copy(rules = listOf(NativeRule(
            id = "browser-break", title = "Browser break", mode = "condition",
            categories = setOf("browsers"), excludedApps = setOf("allowed.browser"),
            blocked = false, allowedUntil = 10_000L,
        )))
        val restored = PlanCodec.decode(PlanCodec.encode(saved))
        assertFalse(restored.blocks("new.browser", setOf("browsers"), now = 9_999L))
        assertTrue(restored.blocks("new.browser", setOf("browsers"), now = 10_000L))
        assertFalse(restored.blocks("allowed.browser", setOf("browsers"), now = 10_000L))
    }
}
