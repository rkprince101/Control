package com.example.control.enforcement

import android.content.Context
import android.content.SharedPreferences
import org.json.JSONArray
import org.json.JSONObject

/**
 * What the block screen says about one blocked app or site.
 *
 * Legacy text comes from Dart; authoritative rules generate current details.
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
 * Enabled native rules plus the legacy Dart snapshot, cached synchronously.
 * Evaluation requires an explicit clock sample rather than a wall-clock default.
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
    /** Null is the legacy snapshot contract; an empty list clears all rules. */
    val rules: List<NativeRule>? = null,
) {
    fun blocks(
        packageName: String,
        categories: Set<String> = emptySet(),
        now: Long,
    ): Boolean = rules?.any { it.isBlocked(now) && it.targets(packageName, categories) }
        ?: blockedPackages.contains(packageName)

    fun effectiveDomains(now: Long): Set<String> =
        rules?.filter { it.isBlocked(now) }?.flatMap { it.blockedDomains }?.toSet()
            ?: blockedDomains

    fun effectivePackages(
        candidates: Set<String>,
        categories: (String) -> Set<String>,
        now: Long,
    ): Set<String> {
        val currentRules = rules ?: return blockedPackages
        val active = currentRules.filter { it.isBlocked(now) }
        return buildSet {
            active.forEach { addAll(it.apps) }
            if (active.any { it.categories.isNotEmpty() }) {
                candidates.forEach { app ->
                    val tokens = categories(app)
                    if (active.any { it.targets(app, tokens) }) add(app)
                }
            }
        }
    }

    fun detailFor(
        key: String,
        categories: Set<String> = emptySet(),
        now: Long,
    ): BlockDetail {
        val currentRules = rules ?: return details[key] ?: BlockDetail.EMPTY
        val matches = currentRules.filter {
            it.isBlocked(now) && (it.targets(key, categories) || key in it.blockedDomains)
        }
        val first = matches.firstOrNull() ?: return BlockDetail.EMPTY
        return first.detail().copy(title = matches.map { it.title }.distinct().joinToString(", "))
    }

    /**
     * Snapshot freshness only. Legacy plans retain their blocks on staleness;
     * authoritative rules evaluate current time instead of trusting the snapshot.
     */
    fun isStale(now: Long) = nextWakeAt in 1 until now

    companion object {
        val EMPTY = Plan(emptySet(), emptySet(), 0L, 0L, emptyMap())
    }
}

class PlanStore(context: Context) {

    private val context = context.applicationContext

    // Re-obtain after unlock: an upgrade can migrate the legacy file while an
    // already-bound direct-boot service still holds this PlanStore.
    private val prefs: SharedPreferences
        get() = EnforcementStorage.preferences(context, PREFS)

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
            .apply { plan.rules?.let { put("rules", encodeRules(it)) } }
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
            rules = json.optJSONArray("rules")?.let(::decodeRules),
        )
    }

    fun encodeRules(rules: List<NativeRule>): JSONArray = JSONArray().apply {
        rules.forEach { rule ->
            put(JSONObject()
                .put("id", rule.id)
                .put("title", rule.title)
                .put("mode", rule.mode)
                .put("apps", JSONArray(rule.apps.toList()))
                .put("categories", JSONArray(rule.categories.toList()))
                .put("excludedApps", JSONArray(rule.excludedApps.toList()))
                .put("blockedDomains", JSONArray(rule.blockedDomains.toList()))
                .put("schedule", JSONArray().apply {
                    rule.schedule.forEach { range ->
                        put(JSONObject()
                            .put("startMinute", range.startMinute)
                            .put("endMinute", range.endMinute)
                            .put("weekdays", JSONArray(range.weekdays.toList())))
                    }
                })
                .put("schedulePolarity", rule.schedulePolarity)
                .put("blocked", rule.blocked)
                .put("allowedUntil", rule.allowedUntil))
        }
    }

    fun decodeRules(array: JSONArray): List<NativeRule> = (0 until array.length()).map { index ->
        val raw = array.getJSONObject(index)
        val mode = raw.getString("mode")
        require(mode in setOf("time", "condition", "place", "device")) { "Unknown rule mode" }
        val polarity = raw.optString("schedulePolarity", "blockDuring")
        require(polarity in setOf("blockDuring", "allowDuring")) { "Unknown schedule polarity" }
        val schedule = raw.optJSONArray("schedule") ?: JSONArray()
        NativeRule(
            id = raw.getString("id"),
            title = raw.optString("title"),
            mode = mode,
            apps = raw.optJSONArray("apps").toStringSet(),
            categories = raw.optJSONArray("categories").toStringSet(),
            excludedApps = raw.optJSONArray("excludedApps").toStringSet(),
            blockedDomains = raw.optJSONArray("blockedDomains").toStringSet(),
            schedule = (0 until schedule.length()).map { i ->
                val range = schedule.getJSONObject(i)
                val days = range.getJSONArray("weekdays")
                NativeTimeRange(
                    range.getInt("startMinute"),
                    range.getInt("endMinute"),
                    (0 until days.length()).map { days.getInt(it) }.toSet(),
                ).also {
                    require(it.startMinute in 0..1439 && it.endMinute in 0..1439)
                    require(it.weekdays.all { day -> day in 1..7 })
                }
            },
            schedulePolarity = polarity,
            blocked = raw.optBoolean("blocked", false),
            allowedUntil = raw.optLong("allowedUntil", 0L),
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
