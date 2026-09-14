package com.example.control.enforcement

import android.content.Context
import android.content.SharedPreferences
import org.json.JSONArray
import org.json.JSONObject

/**
 * What the block screen says about one blocked app or site.
 *
 * Computed in Dart, where the rules live, and carried down as text. The screen
 * has to explain itself the instant it appears, and the enforcer has no way to
 * evaluate a rule on its own.
 */
data class BlockDetail(
    /** The name of the block that is doing this. */
    val title: String,
    /** One line saying why, and when it ends. */
    val status: String,
    /** 0..100 for a habit in progress, or -1 when there is nothing to show. */
    val progressPercent: Int,
    /** Wall-clock millis when this lifts on its own, or 0 when it will not. */
    val unlockAt: Long,
) {
    companion object {
        val EMPTY = BlockDetail("", "", -1, 0L)
    }
}

/**
 * The materialised output of the Dart rule engine, cached where native code can
 * read it synchronously.
 */
data class Plan(
    val blockedPackages: Set<String>,
    /** Hosts the browser guard turns away, as bare domains. */
    val blockedDomains: Set<String>,
    /** Wall-clock millis when the plan can change on its own; 0 when nothing is time-driven. */
    val nextWakeAt: Long,
    val updatedAt: Long,
    /** Keyed by package name, and by domain for the browser guard. */
    val details: Map<String, BlockDetail>,
) {
    fun blocks(packageName: String) = blockedPackages.contains(packageName)

    fun detailFor(key: String) = details[key] ?: BlockDetail.EMPTY

    /**
     * A plan whose wake time has passed is stale: the schedule moved on but
     * nobody recomputed. Callers keep enforcing it anyway and trigger a
     * refresh, because dropping the shield on staleness is exactly the bypass
     * a user would learn to trigger on purpose.
     */
    fun isStale(now: Long) = nextWakeAt in 1 until now

    companion object {
        val EMPTY = Plan(emptySet(), emptySet(), 0L, 0L, emptyMap())
    }
}

class PlanStore(context: Context) {

    private val prefs: SharedPreferences =
        context.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    /**
     * Parsed form of [cachedRaw], and nothing more.
     *
     * The cache is keyed by the stored string rather than held outright. The
     * accessibility service and the Flutter bridge each construct their own
     * PlanStore, and an unkeyed cache meant the service read the plan once on
     * its first window event and never saw another edit: apps removed from a
     * block stayed blocked until the service was restarted. Comparing the raw
     * string is cheap, and correctness here is worth more than the comparison.
     */
    private var cachedRaw: String? = null
    private var cachedPlan: Plan = Plan.EMPTY

    @Synchronized
    fun read(): Plan {
        val raw = prefs.getString(KEY_PLAN, null) ?: return Plan.EMPTY
        if (raw == cachedRaw) return cachedPlan

        val plan = runCatching { PlanCodec.decode(raw) }.getOrDefault(Plan.EMPTY)
        cachedRaw = raw
        cachedPlan = plan
        return plan
    }

    @Synchronized
    fun write(plan: Plan) {
        val raw = PlanCodec.encode(plan)
        cachedRaw = raw
        cachedPlan = plan
        // apply() writes to disk in the background but updates the in-memory
        // map immediately, so a read from the service sees this at once.
        prefs.edit().putString(KEY_PLAN, raw).apply()
    }

    private companion object {
        const val PREFS = "control_enforcement"
        const val KEY_PLAN = "plan"
    }
}

/** Plan serialisation, kept pure so it can be tested on the JVM. */
object PlanCodec {

    fun encode(plan: Plan): String {
        val details = JSONObject()
        plan.details.forEach { (key, detail) ->
            details.put(
                key,
                JSONObject()
                    .put(FIELD_TITLE, detail.title)
                    .put(FIELD_STATUS, detail.status)
                    .put(FIELD_PROGRESS, detail.progressPercent)
                    .put(FIELD_UNLOCK_AT, detail.unlockAt),
            )
        }

        return JSONObject()
            .put(FIELD_PACKAGES, JSONArray(plan.blockedPackages.toList()))
            .put(FIELD_DOMAINS, JSONArray(plan.blockedDomains.toList()))
            .put(FIELD_NEXT_WAKE, plan.nextWakeAt)
            .put(FIELD_UPDATED_AT, plan.updatedAt)
            .put(FIELD_DETAILS, details)
            .toString()
    }

    fun decode(raw: String): Plan {
        val json = JSONObject(raw)

        val detailsJson = json.optJSONObject(FIELD_DETAILS) ?: JSONObject()
        val details = buildMap {
            detailsJson.keys().forEach { key ->
                val entry = detailsJson.optJSONObject(key) ?: return@forEach
                put(
                    key,
                    BlockDetail(
                        title = entry.optString(FIELD_TITLE),
                        status = entry.optString(FIELD_STATUS),
                        progressPercent = entry.optInt(FIELD_PROGRESS, -1),
                        unlockAt = entry.optLong(FIELD_UNLOCK_AT, 0L),
                    ),
                )
            }
        }

        return Plan(
            blockedPackages = json.optJSONArray(FIELD_PACKAGES).toStringSet(),
            blockedDomains = json.optJSONArray(FIELD_DOMAINS).toStringSet(),
            nextWakeAt = json.optLong(FIELD_NEXT_WAKE, 0L),
            updatedAt = json.optLong(FIELD_UPDATED_AT, 0L),
            details = details,
        )
    }

    private fun JSONArray?.toStringSet(): Set<String> {
        if (this == null) return emptySet()
        return buildSet {
            for (i in 0 until length()) add(getString(i))
        }
    }

    private const val FIELD_PACKAGES = "packages"
    private const val FIELD_DOMAINS = "domains"
    private const val FIELD_NEXT_WAKE = "nextWakeAt"
    private const val FIELD_UPDATED_AT = "updatedAt"
    private const val FIELD_DETAILS = "details"
    private const val FIELD_TITLE = "title"
    private const val FIELD_STATUS = "status"
    private const val FIELD_PROGRESS = "progress"
    private const val FIELD_UNLOCK_AT = "unlockAt"
}
