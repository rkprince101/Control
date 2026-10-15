package com.rkprince.control.insights

import android.app.Activity
import android.content.Intent
import android.graphics.Color
import android.net.Uri
import android.os.Bundle
import android.util.TypedValue
import android.view.Gravity
import android.widget.Button
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import com.rkprince.control.EdgeToEdge
import com.rkprince.control.R

/**
 * What Health Connect shows when someone asks why Control wants their
 * workouts and mindfulness sessions. Health Connect will not offer its
 * permission screen to an app that has no such page.
 */
class HealthRationaleActivity : Activity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        EdgeToEdge.apply(window, darkContent = false)
        val density = resources.displayMetrics.density
        fun dp(value: Int) = (value * density).toInt()

        val column = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(24), dp(48), dp(24), dp(32))
            setBackgroundColor(BACKGROUND)
        }
        column.addView(
            TextView(this).apply {
                text = getString(R.string.health_rationale_title)
                setTextColor(FOREGROUND)
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 24f)
                setPadding(0, 0, 0, dp(16))
            },
        )
        column.addView(
            TextView(this).apply {
                text = getString(R.string.health_rationale_body)
                setTextColor(MUTED)
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 16f)
                setLineSpacing(dp(4).toFloat(), 1f)
            },
        )
        column.addView(
            Button(this).apply {
                text = getString(R.string.health_rationale_policy)
                isAllCaps = false
                gravity = Gravity.CENTER
                setOnClickListener {
                    runCatching {
                        startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(PRIVACY_URL)))
                    }
                }
                layoutParams = LinearLayout.LayoutParams(
                    LinearLayout.LayoutParams.WRAP_CONTENT,
                    LinearLayout.LayoutParams.WRAP_CONTENT,
                ).apply { topMargin = dp(24) }
            },
        )
        setContentView(
            ScrollView(this).apply {
                setBackgroundColor(BACKGROUND)
                fitsSystemWindows = true
                addView(column)
            },
        )
    }

    private companion object {
        const val PRIVACY_URL = "https://github.com/rkprince101/Control/blob/main/PRIVACY.md"
        val BACKGROUND = Color.parseColor("#111612")
        val FOREGROUND = Color.parseColor("#F1F3E9")
        val MUTED = Color.parseColor("#B8C4B5")
    }
}
