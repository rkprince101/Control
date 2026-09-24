package com.example.control.enforcement

import android.content.Context
import android.os.SystemClock
import android.provider.Settings

/**
 * One clock for every native enforcement surface in this app process.
 *
 * elapsedRealtime includes deep sleep. A persisted boot count lets a restarted
 * process resume its epoch/uptime anchor without trusting a changed wall clock.
 * Schedules convert this epoch to the current local timezone on each evaluation;
 * timezone and DST changes do not reset the epoch anchor.
 *
 * After reboot (or when boot identity is unavailable), uptime cannot recover
 * powered-off time. We must trust wall time, floored by the last checkpoint.
 * Without a trusted external clock, a forward clock change across reboot cannot
 * be distinguished from real elapsed time. Only checkpointed progress survives
 * reboot: writes are bounded to once per minute while sampled, not during sleep
 * or while the app is stopped, and disk flushes are asynchronous.
 */
object EnforcementClock {
    private var clock: EnforcementTime? = null
    private var storageGeneration = -1

    @Synchronized
    fun now(context: Context): Long {
        val app = context.applicationContext
        val prefs = EnforcementStorage.preferences(app, "control_enforcement_clock")
        val elapsed = SystemClock.elapsedRealtime()
        val liveEpoch = clock?.now(elapsed)
        if (storageGeneration != EnforcementStorage.generation) {
            // On the first unlock after upgrading, adopt the migrated anchor
            // rather than retaining a pre-unlock, empty-storage clock.
            clock = null
            storageGeneration = EnforcementStorage.generation
        }
        val current = clock ?: EnforcementTime(
            wallMillis = System.currentTimeMillis(),
            elapsedMillis = elapsed,
            minimumEpochMillis = PlanStore(app).read().updatedAt,
            liveEpochMillis = liveEpoch,
            bootCount = runCatching {
                Settings.Global.getInt(app.contentResolver, Settings.Global.BOOT_COUNT, -1)
            }.getOrDefault(-1),
            saved = if (prefs.contains("epochMillis")) {
                ClockCheckpoint(
                    prefs.getLong("epochMillis", 0L),
                    prefs.getLong("elapsedMillis", 0L),
                    prefs.getInt("bootCount", -1),
                )
            } else {
                // An existing installation already observed the persisted plan timestamp.
                PlanStore(app).read().updatedAt.takeIf { it > 0L }?.let {
                    ClockCheckpoint(it, 0L, -1)
                }
            },
        ).also { clock = it }
        val now = current.now(elapsed)
        current.checkpointIfDue(elapsed)?.let {
            prefs.edit()
                .putLong("epochMillis", it.epochMillis)
                .putLong("elapsedMillis", it.elapsedMillis)
                .putInt("bootCount", it.bootCount)
                .apply()
        }
        return now
    }
}

internal data class ClockCheckpoint(val epochMillis: Long, val elapsedMillis: Long, val bootCount: Int)

/** Pure policy. Wall time is sampled only when restoring/creating the anchor. */
internal class EnforcementTime(
    wallMillis: Long,
    private val elapsedMillis: Long,
    private val bootCount: Int,
    saved: ClockCheckpoint? = null,
    minimumEpochMillis: Long = 0L,
    liveEpochMillis: Long? = null,
) {
    private val canResume = saved != null && bootCount >= 0 && saved.bootCount == bootCount &&
        saved.elapsedMillis >= 0 && elapsedMillis >= saved.elapsedMillis
    private val restoredEpoch = if (canResume) {
        saved!!.epochMillis + (elapsedMillis - saved.elapsedMillis)
    } else {
        // Unlock migration is not a reboot. Preserve an already-running uptime
        // anchor instead of trusting a wall clock edited during the lock screen.
        val current = liveEpochMillis ?: wallMillis
        maxOf(current, saved?.epochMillis ?: current)
    }
    private val epochMillis = maxOf(restoredEpoch, minimumEpochMillis, liveEpochMillis ?: Long.MIN_VALUE)
    private var highWater = epochMillis
    private var lastCheckpointElapsed =
        if (canResume && epochMillis == restoredEpoch) saved!!.elapsedMillis else null

    fun now(elapsedNow: Long): Long {
        highWater = maxOf(highWater, epochMillis + maxOf(0L, elapsedNow - elapsedMillis))
        return highWater
    }

    fun checkpointIfDue(elapsedNow: Long): ClockCheckpoint? {
        val last = lastCheckpointElapsed
        if (last != null && elapsedNow - last < CHECKPOINT_INTERVAL_MS) return null
        lastCheckpointElapsed = elapsedNow
        return ClockCheckpoint(now(elapsedNow), elapsedNow, bootCount)
    }

    companion object {
        const val CHECKPOINT_INTERVAL_MS = 60_000L
    }
}
