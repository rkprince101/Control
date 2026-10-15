package com.rkprince.control.thoughts

import com.rkprince.control.enforcement.NativeRule
import com.rkprince.control.enforcement.Plan
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class ThoughtTest {
    private val app = Thought(
        id = "a",
        text = "Reply to Sam",
        createdAt = 1_000L,
        packageName = "video.app",
        target = "video.app",
        label = "Video",
        blockTitle = "Evenings",
    )
    private val site = app.copy(id = "s", packageName = "browser.app", target = "news.example", label = "news.example")
    private val manual = Thought(id = "m", text = "Call the bank", createdAt = 2_000L)

    private fun plan(vararg rules: NativeRule) =
        Plan(emptySet(), emptySet(), 0L, 0L, emptyMap(), rules = rules.toList())

    @Test fun `thoughts round trip`() {
        val back = ThoughtCodec.decode(ThoughtCodec.encode(listOf(app, site.copy(doneAt = 5L), manual)))
        assertEquals(listOf(app, site.copy(doneAt = 5L), manual), back)
    }

    @Test fun `unreadable entries are dropped, not the whole list`() {
        val raw = """[{"id":"a","text":"Keep"},{"id":"","text":"No id"},{"id":"b","text":"  "},"junk"]"""
        assertEquals(listOf("a"), ThoughtCodec.decode(raw).map { it.id })
        assertTrue(ThoughtCodec.decode("not json").isEmpty())
        assertTrue(ThoughtCodec.decode(null).isEmpty())
    }

    @Test fun `trimming drops the oldest finished thoughts before any open one`() {
        val many = (1..ThoughtCodec.MAX_THOUGHTS + 3).map {
            Thought(id = "t$it", text = "x", createdAt = it.toLong(), doneAt = if (it <= 5) 1L else 0L)
        }
        val kept = ThoughtCodec.trim(many)
        assertEquals(ThoughtCodec.MAX_THOUGHTS, kept.size)
        // The five done ones were the oldest; three of them had to go, no open one did.
        assertEquals(2, kept.count { it.doneAt != 0L })
        assertEquals(many.size.toLong(), kept.first().createdAt)
    }

    @Test fun `an app thought follows its app's block`() {
        val blocking = NativeRule("r", "Evenings", "condition", apps = setOf("video.app"), blocked = true)
        assertTrue(ThoughtStatus.blocked(app, plan(blocking), emptySet(), 10L))
        assertFalse(ThoughtStatus.blocked(app, plan(blocking.copy(blocked = false)), emptySet(), 10L))
        assertFalse(ThoughtStatus.blocked(app, plan(), emptySet(), 10L))
    }

    @Test fun `a category block counts for an app thought`() {
        val browsers = NativeRule("r", "Browsing", "condition", categories = setOf("browsers"), blocked = true)
        assertTrue(ThoughtStatus.blocked(app, plan(browsers), setOf("browsers"), 10L))
        assertFalse(ThoughtStatus.blocked(app, plan(browsers), emptySet(), 10L))
    }

    @Test fun `a site thought follows the site, not the browser`() {
        val sites = NativeRule("r", "News", "condition", blockedDomains = setOf("news.example"), blocked = true)
        assertTrue(ThoughtStatus.isSite(site))
        assertTrue(ThoughtStatus.blocked(site, plan(sites), emptySet(), 10L))
        // The browser itself being blocked says nothing about the site.
        val browser = NativeRule("b", "Browser", "condition", apps = setOf("browser.app"), blocked = true)
        assertFalse(ThoughtStatus.blocked(site, plan(browser), emptySet(), 10L))
    }

    @Test fun `a thought parked inside Control is never blocked`() {
        val everything = NativeRule("r", "All", "condition", categories = setOf("all_apps"), blocked = true)
        assertFalse(ThoughtStatus.blocked(manual, plan(everything), setOf("all_apps"), 10L))
        assertFalse(ThoughtStatus.isSite(manual))
    }

    @Test fun `text is trimmed and capped when read back`() {
        val long = "y".repeat(ThoughtCodec.MAX_LENGTH + 50)
        val back = ThoughtCodec.fromJson(ThoughtCodec.toJson(manual.copy(text = "  $long  ")))
        assertEquals(ThoughtCodec.MAX_LENGTH, back!!.text.length)
        assertNull(ThoughtCodec.fromJson(ThoughtCodec.toJson(manual.copy(text = "   "))))
    }
}
