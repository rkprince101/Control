package com.rkprince.control.enforcement

import java.util.Locale

/**
 * Website blocking, decided in pure Kotlin so it can be unit-tested.
 *
 * Blocking Instagram the app and leaving instagram.com open in Chrome is the
 * loophole every tool of this kind has, and the first one anyone finds. This
 * closes it by reading the browser's address bar, which is cheap, works in
 * incognito, and needs no VPN. It does not see inside a page, so a link opened
 * in an in-app webview is still a way through.
 */
object WebRules {

    /**
     * Browsers whose address bar can be read, mapped to the view id that holds
     * it. Anything not on this list is not watched at all.
     */
    val browserUrlBars = mapOf(
        "com.android.chrome" to "com.android.chrome:id/url_bar",
        "com.chrome.beta" to "com.chrome.beta:id/url_bar",
        "com.chrome.dev" to "com.chrome.dev:id/url_bar",
        "com.brave.browser" to "com.brave.browser:id/url_bar",
        "com.microsoft.emmx" to "com.microsoft.emmx:id/url_bar",
        "com.opera.browser" to "com.opera.browser:id/url_field",
        "com.opera.mini.native" to "com.opera.mini.native:id/url_field",
        "com.duckduckgo.mobile.android" to
            "com.duckduckgo.mobile.android:id/omnibarTextInput",
        "com.sec.android.app.sbrowser" to
            "com.sec.android.app.sbrowser:id/location_bar_edit_text",
        "org.mozilla.firefox" to
            "org.mozilla.firefox:id/mozac_browser_toolbar_url_view",
        "org.mozilla.focus" to
            "org.mozilla.focus:id/mozac_browser_toolbar_url_view",
        "com.vivaldi.browser" to "com.vivaldi.browser:id/url_bar",
        "com.kiwibrowser.browser" to "com.kiwibrowser.browser:id/url_bar",
    )

    fun isBrowser(packageName: String) = packageName in browserUrlBars

    /**
     * Reduces whatever the address bar shows to a bare host.
     *
     * The bar may hold a full URL, a host with the scheme hidden, or a search
     * query. Anything that is not host-shaped returns null rather than being
     * guessed at, because a false positive here closes the user's browser.
     */
    fun hostOf(barText: String?): String? {
        var text = barText?.trim()?.lowercase(Locale.ROOT) ?: return null
        if (text.isEmpty()) return null

        // A space means a search query, not an address.
        if (text.contains(' ')) return null

        text = text.substringAfter("://")
        text = text.substringBefore('/')
        text = text.substringBefore('?')
        // Strip credentials and port.
        text = text.substringAfterLast('@').substringBefore(':')
        if (text.startsWith("www.")) text = text.removePrefix("www.")

        if (text.isEmpty() || !text.contains('.')) return null
        if (text.any { it != '.' && it != '-' && !it.isLetterOrDigit() }) return null
        return text
    }

    /**
     * True when [host] is the blocked domain or any subdomain of it, so
     * `instagram.com` also covers `www.instagram.com` and `m.instagram.com`
     * without the user listing each one.
     */
    fun matches(host: String?, blockedDomains: Set<String>): String? {
        if (host == null) return null
        for (raw in blockedDomains) {
            val domain = normaliseDomain(raw) ?: continue
            if (host == domain || host.endsWith(".$domain")) return domain
        }
        return null
    }

    /** Accepts what a user actually types: `https://Instagram.com/`, `WWW.X.COM`. */
    fun normaliseDomain(raw: String): String? = hostOf(raw)
}
