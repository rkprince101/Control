package com.example.control.enforcement

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * A false positive here closes the user's browser on an innocent page, so the
 * "not a host" cases matter as much as the matches.
 */
class WebRulesTest {

    private val blocked = setOf("instagram.com", "https://YouTube.com/")

    @Test
    fun `a bare host is extracted`() {
        assertEquals("instagram.com", WebRules.hostOf("instagram.com"))
    }

    @Test
    fun `scheme, www, path, query and port are stripped`() {
        assertEquals(
            "instagram.com",
            WebRules.hostOf("https://www.instagram.com:443/reels/?hl=en"),
        )
    }

    @Test
    fun `a search query is not a host`() {
        assertNull(WebRules.hostOf("how to stop scrolling instagram.com"))
        assertNull(WebRules.hostOf("instagram"))
        assertNull(WebRules.hostOf(""))
        assertNull(WebRules.hostOf(null))
    }

    @Test
    fun `a domain covers its subdomains`() {
        assertEquals(
            "instagram.com",
            WebRules.matches("m.instagram.com", blocked),
        )
        assertEquals(
            "instagram.com",
            WebRules.matches("instagram.com", blocked),
        )
    }

    @Test
    fun `a domain does not cover a lookalike`() {
        // The classic suffix bug: notinstagram.com must not match.
        assertNull(WebRules.matches("notinstagram.com", blocked))
        assertNull(WebRules.matches("instagram.com.evil.example", blocked))
    }

    @Test
    fun `domains the user typed loosely still match`() {
        assertEquals("youtube.com", WebRules.matches("m.youtube.com", blocked))
    }

    @Test
    fun `unrelated sites are left alone`() {
        assertNull(WebRules.matches("wikipedia.org", blocked))
    }

    @Test
    fun `only known browsers are watched`() {
        assertTrue(WebRules.isBrowser("com.android.chrome"))
        assertTrue(WebRules.isBrowser("org.mozilla.firefox"))
        assertFalse(WebRules.isBrowser("com.instagram.android"))
    }
}
