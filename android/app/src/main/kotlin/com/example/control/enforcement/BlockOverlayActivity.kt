package com.example.control.enforcement

import android.animation.ObjectAnimator
import android.annotation.SuppressLint
import android.app.Activity
import android.content.Intent
import android.graphics.Color
import android.graphics.drawable.GradientDrawable
import android.os.Bundle
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.UserManager
import android.window.OnBackInvokedDispatcher
import android.util.TypedValue
import android.view.Gravity
import android.view.ViewGroup
import android.widget.Button
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.ProgressBar
import android.widget.ScrollView
import android.widget.TextView
import com.example.control.R
import com.example.control.insights.AppCategoryResolver
import java.util.Locale
import java.util.concurrent.TimeUnit

/**
 * The screen the user hits instead of the app they opened.
 *
 * Native and built in code rather than a Flutter route: it has to be on screen
 * before the blocked app finishes drawing its first frame, and starting a
 * Flutter engine loses that race. It also has to work when the main app process
 * is dead.
 *
 * It says why, not just no. A screen that only refuses reads as a malfunction;
 * one that says "unlocks at 5:00 PM" or "3,200 of 5,000 steps" is the rule
 * doing its job, and the countdown is the part that makes people close the
 * phone instead of hunting for a way around it.
 */
class BlockOverlayActivity : Activity() {

    private val handler = Handler(Looper.getMainLooper())
    private var countdown: TextView? = null
    private var unlockAt = 0L
    private val planStore by lazy { PlanStore(this) }
    private val categories by lazy { AppCategoryResolver(this) }
    private var blockedPackage = ""
    private var detailKey = ""
    private var currentDetail: BlockDetail? = null

    private val tick = object : Runnable {
        override fun run() {
            if (!refreshBlock()) return
            handler.postDelayed(this, 1000L)
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        blockedPackage = intent.getStringExtra(EXTRA_PACKAGE).orEmpty()
        detailKey = intent.getStringExtra(EXTRA_DETAIL_KEY) ?: blockedPackage
        if (!refreshBlock()) return
        handler.postDelayed(tick, 1000L)

        // Android 13 introduced predictive back, and onBackPressed stops being
        // called once an app opts in. Registering here keeps back behaving like
        // Home on new releases as well as old ones.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            onBackInvokedDispatcher.registerOnBackInvokedCallback(
                OnBackInvokedDispatcher.PRIORITY_DEFAULT,
            ) { goHome() }
        }
    }

    override fun onDestroy() {
        handler.removeCallbacks(tick)
        super.onDestroy()
    }

    private fun refreshBlock(): Boolean {
        if (getSystemService(UserManager::class.java)?.isUserUnlocked != true &&
            !categories.canBlockBeforeUnlock(blockedPackage)) {
            finish()
            return false
        }
        val plan = planStore.read()
        val now = EnforcementClock.now(this)
        val tokens = if (plan.rules?.any { it.categories.isNotEmpty() } == true) {
            categories.categories(blockedPackage)
        } else emptySet()
        val appBlocked = plan.blocks(blockedPackage, tokens, now)
        val domain = if (detailKey != blockedPackage) {
            WebRules.matches(detailKey, plan.effectiveDomains(now))
        } else null
        if (!appBlocked && domain == null) {
            finish()
            return false
        }
        val detail = plan.detailFor(
            if (appBlocked) blockedPackage else domain!!,
            if (appBlocked) tokens else emptySet(),
            now,
        )
        if (detail != currentDetail) {
            currentDetail = detail
            unlockAt = detail.unlockAt
            countdown = null
            setContentView(buildLayout(blockedPackage, detail))
        }
        renderCountdown(now)
        return true
    }

    private fun buildLayout(blockedPackage: String, detail: BlockDetail): ViewGroup {
        val density = resources.displayMetrics.density
        fun dp(value: Int) = (value * density).toInt()

        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            setBackgroundColor(BACKGROUND)
            setPadding(dp(20), dp(24), dp(20), dp(24))
        }

        val card = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER_HORIZONTAL
            setPadding(dp(20), dp(28), dp(20), dp(24))
            background = GradientDrawable().apply {
                cornerRadius = dp(32).toFloat()
                setColor(CARD)
            }
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT,
            )
        }

        appIcon(blockedPackage)?.let { icon ->
            card.addView(
                ImageView(this).apply {
                    setImageDrawable(icon)
                    layoutParams = LinearLayout.LayoutParams(dp(56), dp(56))
                        .apply { bottomMargin = dp(16) }
                    alpha = 0.85f
                },
            )
        }

        card.addView(
            TextView(this).apply {
                text = "Take a moment"
                setTextColor(ACCENT)
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 30f)
                gravity = Gravity.CENTER
                typeface = android.graphics.Typeface.create("sans-serif-medium", android.graphics.Typeface.NORMAL)
                setPadding(0, 0, 0, dp(12))
            },
        )

        card.addView(
            TextView(this).apply {
                text = labelFor(blockedPackage)
                setTextColor(FOREGROUND)
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 20f)
                gravity = Gravity.CENTER
                typeface = android.graphics.Typeface.DEFAULT_BOLD
            },
        )

        if (detail.title.isNotEmpty()) {
            card.addView(
                TextView(this).apply {
                    text = getString(R.string.block_by, detail.title)
                    setTextColor(MUTED)
                    setTextSize(TypedValue.COMPLEX_UNIT_SP, 14f)
                    gravity = Gravity.CENTER
                    setPadding(0, dp(6), 0, 0)
                },
            )
        }

        val status = detail.status.ifEmpty { getString(R.string.block_default_reason) }
        card.addView(
            TextView(this).apply {
                text = status
                setTextColor(FOREGROUND)
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 16f)
                gravity = Gravity.CENTER
                setLineSpacing(dp(4).toFloat(), 1f)
                setPadding(dp(4), dp(18), dp(4), 0)
            },
        )

        if (detail.progressPercent >= 0) {
            card.addView(progressBar(detail.progressPercent, dp(12), dp(20)))
            card.addView(
                TextView(this).apply {
                    text = getString(R.string.block_progress, detail.progressPercent)
                    setTextColor(ACCENT)
                    setTextSize(TypedValue.COMPLEX_UNIT_SP, 14f)
                    gravity = Gravity.CENTER
                    setPadding(0, dp(8), 0, 0)
                },
            )
        }

        if (unlockAt > 0) {
            countdown = TextView(this).apply {
                setTextColor(ACCENT)
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 24f)
                typeface = android.graphics.Typeface.create("sans-serif-medium", android.graphics.Typeface.NORMAL)
                gravity = Gravity.CENTER
                setPadding(0, dp(16), 0, 0)
            }
            card.addView(countdown)
        }

        card.addView(
            Button(this).apply {
                text = getString(R.string.block_go_home)
                setTextColor(BACKGROUND)
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 16f)
                isAllCaps = false
                minHeight = dp(48)
                minimumHeight = dp(48)
                setPadding(dp(20), dp(12), dp(20), dp(12))
                background = GradientDrawable().apply {
                    cornerRadius = dp(24).toFloat()
                    setColor(ACCENT)
                }
                setOnClickListener { goHome() }
                layoutParams = LinearLayout.LayoutParams(
                    LinearLayout.LayoutParams.MATCH_PARENT,
                    LinearLayout.LayoutParams.WRAP_CONTENT,
                ).apply { topMargin = dp(26) }
            },
        )

        root.addView(card)
        return ScrollView(this).apply {
            setBackgroundColor(BACKGROUND)
            isFillViewport = true
            addView(root)
        }
    }

    private fun progressBar(percent: Int, height: Int, topMargin: Int) =
        ProgressBar(this, null, android.R.attr.progressBarStyleHorizontal).apply {
            max = 100
            progressDrawable?.setTint(ACCENT)
            progressTintList = android.content.res.ColorStateList.valueOf(ACCENT)
            progressBackgroundTintList =
                android.content.res.ColorStateList.valueOf(RAISED)
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                height,
            ).apply { this.topMargin = topMargin }

            // Animated rather than set, so the bar reads as progress made
            // rather than as a static bar of unclear meaning.
            ObjectAnimator.ofInt(this, "progress", 0, percent).apply {
                duration = 700
                start()
            }
        }

    /** Returns false when there is nothing left to count down to. */
    private fun renderCountdown(now: Long): Boolean {
        val view = countdown ?: return false
        val remaining = unlockAt - now

        if (remaining <= 0) {
            view.text = getString(R.string.block_unlocking)
            return false
        }

        val hours = TimeUnit.MILLISECONDS.toHours(remaining)
        val minutes = TimeUnit.MILLISECONDS.toMinutes(remaining) % 60
        val seconds = TimeUnit.MILLISECONDS.toSeconds(remaining) % 60

        view.text = getString(
            R.string.block_countdown,
            if (hours > 0) {
                String.format(Locale.US, "%d:%02d:%02d", hours, minutes, seconds)
            } else {
                String.format(Locale.US, "%02d:%02d", minutes, seconds)
            },
        )
        return true
    }

    private fun appIcon(blockedPackage: String) = runCatching {
        packageManager.getApplicationIcon(blockedPackage)
    }.getOrNull()

    private fun labelFor(blockedPackage: String): String {
        if (blockedPackage.isEmpty()) return getString(R.string.block_fallback_title)
        return runCatching {
            val info = packageManager.getApplicationInfo(blockedPackage, 0)
            packageManager.getApplicationLabel(info).toString()
        }.getOrDefault(blockedPackage)
    }

    private fun goHome() {
        startActivity(
            Intent(Intent.ACTION_MAIN).apply {
                addCategory(Intent.CATEGORY_HOME)
                flags = Intent.FLAG_ACTIVITY_NEW_TASK
            },
        )
        finish()
    }

    /**
     * Back must not reveal the blocked app sitting behind this screen, so it
     * behaves like Home instead of popping the task.
     *
     * Still needed below Android 13, where the dispatcher above does not exist.
     */
    @Suppress("DEPRECATION", "OVERRIDE_DEPRECATION")
    @SuppressLint("GestureBackNavigation")
    override fun onBackPressed() {
        goHome()
    }

    /**
     * Anything that takes focus away closes this screen, so it never lingers
     * over an unrelated app.
     */
    override fun onPause() {
        handler.removeCallbacks(tick)
        super.onPause()
        finish()
    }

    companion object {
        const val EXTRA_PACKAGE = "package"

        /** Package name for an app block, or the domain for a site block. */
        const val EXTRA_DETAIL_KEY = "detailKey"

        private val BACKGROUND = Color.parseColor("#111612")
        private val CARD = Color.parseColor("#1A211B")
        private val RAISED = Color.parseColor("#303B31")
        private val FOREGROUND = Color.parseColor("#F1F3E9")
        private val MUTED = Color.parseColor("#B8C4B5")
        private val ACCENT = Color.parseColor("#D8ECC2")
    }
}
