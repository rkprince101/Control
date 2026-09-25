package com.rkprince.control.enforcement

import com.rkprince.control.insights.AppCategoryRules
import org.junit.Assert.*
import org.junit.Test

class AppCategoryRulesTest {
    @Test fun `essential apps never receive category targets`() {
        assertTrue(AppCategoryRules.categories(true, true, true, true).isEmpty())
    }

    @Test fun `all apps requires launcher while browser and game require capabilities`() {
        assertEquals(setOf("all_apps"), AppCategoryRules.categories(true, false, false, false))
        assertTrue(AppCategoryRules.categories(false, false, false, false).isEmpty())
        assertEquals(setOf("browsers"), AppCategoryRules.categories(false, false, true, false))
        assertEquals(setOf("games", "all_apps"), AppCategoryRules.categories(true, false, false, true))
        assertEquals(setOf("browsers", "games", "all_apps"), AppCategoryRules.categories(true, false, true, true))
    }
}
