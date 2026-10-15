package com.rkprince.control.thoughts

import android.content.Context
import android.content.SharedPreferences
import com.rkprince.control.enforcement.Plan
import com.rkprince.control.enforcement.WebRules
import org.json.JSONArray
import org.json.JSONObject

/**
 * Something the user meant to do in a blocked app, written down on the block
 * screen instead, to pick up once the app opens again.
 *
 * [packageName] is the app that was blocked (the browser, for a site), and
 * [target] what the block was on: the package again, or the site's domain.
 * Both are empty for a thought parked from inside Control.
 */
data class Thought(
    val id: String,
    val text: String,
    val createdAt: Long,
    val packageName: String = "",
    val target: String = "",
    val label: String = "",
    val blockTitle: String = "",
    /** Wall-clock millis it was ticked off, or 0 while still open. */
    val doneAt: Long = 0L,
)

/** Thought serialisation, kept pure so it is tested on the JVM. */
object ThoughtCodec {

    fun encode(thoughts: List<Thought>): String = JSONArray().apply {
        thoughts.forEach { put(toJson(it)) }
    }.toString()

    fun decode(raw: String?): List<Thought> {
        if (raw.isNullOrBlank()) return emptyList()
        val array = runCatching { JSONArray(raw) }.getOrNull() ?: return emptyList()
        return (0 until array.length()).mapNotNull { index ->
            array.optJSONObject(index)?.let(::fromJson)
        }
    }

    fun toJson(thought: Thought): JSONObject = JSONObject()
        .put("id", thought.id)
        .put("text", thought.text)
        .put("createdAt", thought.createdAt)
        .put("packageName", thought.packageName)
        .put("target", thought.target)
        .put("label", thought.label)
        .put("blockTitle", thought.blockTitle)
        .put("doneAt", thought.doneAt)

    /** One unreadable entry is dropped rather than taking the rest with it. */
    fun fromJson(json: JSONObject): Thought? {
        val id = json.optString("id")
        val text = json.optString("text").trim()
        if (id.isEmpty() || text.isEmpty()) return null
        return Thought(
            id = id,
            text = text.take(MAX_LENGTH),
            createdAt = json.optLong("createdAt", 0L),
            packageName = json.optString("packageName"),
            target = json.optString("target"),
            label = json.optString("label"),
            blockTitle = json.optString("blockTitle"),
            doneAt = json.optLong("doneAt", 0L).coerceAtLeast(0L),
        )
    }

    /**
     * Newest first, and no more than [MAX_THOUGHTS]: the oldest finished ones
     * go first, then the oldest open ones, so a full list never silently eats
     * something still waiting to be done.
     */
    fun trim(thoughts: List<Thought>): List<Thought> {
        val sorted = thoughts.sortedByDescending { it.createdAt }
        if (sorted.size <= MAX_THOUGHTS) return sorted
        val open = sorted.filter { it.doneAt == 0L }
        val done = sorted.filter { it.doneAt != 0L }
        val keepDone = (MAX_THOUGHTS - open.size).coerceAtLeast(0)
        return (open.take(MAX_THOUGHTS) + done.take(keepDone))
            .sortedByDescending { it.createdAt }
    }

    const val MAX_LENGTH = 1000
    const val MAX_THOUGHTS = 500
}

/** Whether a thought's app or site is still behind a block. */
object ThoughtStatus {

    /**
     * [categories] are the app's category tokens, needed only when a rule
     * blocks by category. A thought parked from inside Control has nothing to
     * wait for and is never blocked.
     */
    fun blocked(thought: Thought, plan: Plan, categories: Set<String>, now: Long): Boolean {
        if (thought.target.isEmpty()) return false
        if (isSite(thought)) {
            return WebRules.matches(thought.target, plan.effectiveDomains(now)) != null
        }
        return plan.blocks(thought.target, categories, now)
    }

    /** A site block parks the domain; an app block parks the package itself. */
    fun isSite(thought: Thought): Boolean =
        thought.target.isNotEmpty() && thought.target != thought.packageName
}

/**
 * The parked thoughts, in the app's own credential-protected storage: they
 * are the user's words, so they stay shut until the phone is first unlocked.
 * The block screen writes here with Flutter not running; the Thoughts page
 * reads and edits through the bridge.
 */
class ThoughtStore(context: Context) {

    private val context = context.applicationContext

    private val prefs: SharedPreferences
        get() = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    fun list(): List<Thought> = synchronized(LOCK) {
        ThoughtCodec.decode(prefs.getString(KEY, null))
    }

    fun add(
        text: String,
        packageName: String = "",
        target: String = "",
        label: String = "",
        blockTitle: String = "",
        now: Long = System.currentTimeMillis(),
    ): Thought? {
        val clean = text.trim().take(ThoughtCodec.MAX_LENGTH)
        if (clean.isEmpty()) return null
        val thought = Thought(
            id = "thought-$now-${(Math.random() * 1_000_000).toInt()}",
            text = clean,
            createdAt = now,
            packageName = packageName,
            target = target,
            label = label,
            blockTitle = blockTitle,
        )
        edit { it + thought }
        return thought
    }

    /** Puts back a thought exactly as it was, the undo after a delete. */
    fun restore(thought: Thought) = edit { list ->
        if (list.any { it.id == thought.id }) list else list + thought
    }

    fun update(id: String, text: String) {
        val clean = text.trim().take(ThoughtCodec.MAX_LENGTH)
        if (clean.isEmpty()) return
        edit { list -> list.map { if (it.id == id) it.copy(text = clean) else it } }
    }

    fun setDone(id: String, done: Boolean, now: Long = System.currentTimeMillis()) = edit { list ->
        list.map { if (it.id == id) it.copy(doneAt = if (done) now else 0L) else it }
    }

    fun delete(id: String) = edit { list -> list.filterNot { it.id == id } }

    fun clearDone() = edit { list -> list.filter { it.doneAt == 0L } }

    private fun edit(change: (List<Thought>) -> List<Thought>) = synchronized(LOCK) {
        val next = ThoughtCodec.trim(change(ThoughtCodec.decode(prefs.getString(KEY, null))))
        // commit, not apply: the block screen finishes straight after writing,
        // and the process may go with it.
        prefs.edit().putString(KEY, ThoughtCodec.encode(next)).commit()
    }

    private companion object {
        const val PREFS = "control_thoughts"
        const val KEY = "thoughts"

        /** The block screen and the bridge share one process and one list. */
        val LOCK = Any()
    }
}
