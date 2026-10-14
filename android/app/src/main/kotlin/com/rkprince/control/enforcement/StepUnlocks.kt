package com.rkprince.control.enforcement

import android.content.Context
import android.content.SharedPreferences
import com.rkprince.control.insights.StepsReader
import org.json.JSONObject

/** An allowance Android granted on its own when a steps goal was reached. */
data class NativeGrant(val grantedAt: Long, val expiresAt: Long)

/**
 * When walking unlocks a rule with Flutter not running. Pure, so it is tested
 * on the JVM alongside the rule evaluation it feeds.
 *
 * Dart owns every other condition and stays the source of truth: it marks a
 * rule with [NativeRule.stepsTarget] only when steps are all that is left, and
 * adopts any allowance minted here the next time it runs, so the two never
 * hand out two allowances for the same day.
 */
object StepUnlockRules {

    /**
     * Today's grants after [stepsToday] steps at [now]: earned ones added,
     * stale ones and ones for rules that no longer exist dropped.
     *
     * Like Dart's, an allowance is one per rule per day. A spent one is kept
     * until the day ends, or the same cumulative steps would buy another.
     */
    fun mint(
        rules: List<NativeRule>,
        grants: Map<String, NativeGrant>,
        stepsToday: Int,
        now: Long,
        dayOf: (Long) -> Int,
        endOfDay: (Long) -> Long,
    ): Map<String, NativeGrant> {
        val today = dayOf(now)
        val ids = rules.mapTo(HashSet()) { it.id }
        val next = grants.filterTo(LinkedHashMap()) { (id, grant) ->
            id in ids && (grant.expiresAt > now || dayOf(grant.grantedAt) == today)
        }
        for (rule in rules) {
            if (rule.mode != "condition" || rule.stepsTarget <= 0 || !rule.blocked) continue
            // Dart already handed out today's allowance.
            if (rule.allowedUntil > 0) continue
            val existing = next[rule.id]
            if (existing != null && dayOf(existing.grantedAt) == today) continue
            if (stepsToday < rule.stepsTarget) continue
            next[rule.id] = NativeGrant(
                grantedAt = now,
                expiresAt = if (rule.unlockForMillis > 0) now + rule.unlockForMillis else endOfDay(now),
            )
        }
        return next
    }
}

/** The plan with native allowances and today's steps folded into its rules. */
fun Plan.withNativeGrants(grants: Map<String, NativeGrant>, stepsToday: Int): Plan = copy(
    rules = rules?.map { it.copy(grantUntil = grants[it.id]?.expiresAt ?: 0L) },
    stepsToday = stepsToday,
)

/** Where native allowances live: device-protected, next to the plan. */
class NativeGrantStore(context: Context) {
    private val context = context.applicationContext

    private val prefs: SharedPreferences
        get() = EnforcementStorage.preferences(context, PREFS)

    fun read(): Map<String, NativeGrant> = synchronized(LOCK) {
        val raw = prefs.getString(KEY, null) ?: return emptyMap()
        if (raw == cachedRaw) return cached
        val parsed = runCatching {
            val json = JSONObject(raw)
            buildMap {
                json.keys().forEach { id ->
                    val entry = json.getJSONObject(id)
                    put(id, NativeGrant(entry.getLong("grantedAt"), entry.getLong("expiresAt")))
                }
            }
        }.getOrDefault(emptyMap())
        cachedRaw = raw
        cached = parsed
        parsed
    }

    fun write(grants: Map<String, NativeGrant>) = synchronized(LOCK) {
        val json = JSONObject()
        grants.forEach { (id, grant) ->
            json.put(id, JSONObject().put("grantedAt", grant.grantedAt).put("expiresAt", grant.expiresAt))
        }
        val raw = json.toString()
        cachedRaw = raw
        cached = grants
        prefs.edit().putString(KEY, raw).apply()
    }

    private companion object {
        const val PREFS = "control_native_grants"
        const val KEY = "grants"
        val LOCK = Any()
        var cachedRaw: String? = null
        var cached: Map<String, NativeGrant> = emptyMap()
    }
}

/** Applies steps to the plan wherever native code evaluates it. */
object StepUnlocks {

    /** [plan] as it stands at [now], with any allowance walking has earned. */
    fun apply(context: Context, plan: Plan, now: Long): Plan {
        val rules = plan.rules ?: return plan
        val store = NativeGrantStore(context)
        val grants = store.read()
        val gated = rules.any { it.stepsTarget > 0 }
        if (!gated && grants.isEmpty()) return plan

        val steps = if (gated) StepsReader(context).todaySoFar(now) else -1
        val next = StepUnlockRules.mint(
            rules = rules,
            grants = grants,
            stepsToday = steps,
            now = now,
            dayOf = { StepsReader.dayKey(it) },
            endOfDay = { StepsReader.endOfDay(it) },
        )
        if (next != grants) store.write(next)
        return plan.withNativeGrants(next, steps)
    }
}
