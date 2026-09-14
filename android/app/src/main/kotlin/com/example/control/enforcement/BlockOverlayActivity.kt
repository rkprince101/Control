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
import android.window.OnBackInvokedDispatcher
import android.util.TypedValue
import android.view.Gravity
import android.view.ViewGroup
import android.widget.Button
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.ProgressBar
import android.widget.TextView
import com.example.control.R
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

    private val tick = object : Runnable {
        override fun run() {
            if (!renderCountdown()) return
            handler.postDelayed(this, 1000L)
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        val blocked = intent.getStringExtra(EXTRA_PACKAGE).orEmpty()
        val detail = PlanStore(this).read().detailFor(
            intent.getStringExtra(EXTRA_DETAIL_KEY) ?: blocked,
        )
        unlockAt = detail.unlockAt

        setContentView(buildLayout(blocked, detail))
        if (unlockAt > 0) handler.post(tick)

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

    private fun buildLayout(blockedPackage: String, detail: BlockDetail): ViewGroup {
        val density = resources.displayMetrics.density
        fun dp(value: Int) = (value * density).toInt()

        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            setBackgroundColor(BACKGROUND)
            setPadding(dp(28), dp(28), dp(28), dp(28))
        }

        val card = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER_HORIZONTAL
            setPadding(dp(24), dp(28), dp(24), dp(24))
            background = GradientDrawable().apply {
                cornerRadius = dp(26).toFloat()
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
                    alpha = 0.65f
                },
            )
        }

        card.addView(
            TextView(this).apply {
                text = labelFor(blockedPackage)
                setTextColor(Color.WHITE)
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 26f)
                gravity = Gravity.CENTER
                typeface = android.graphics.Typeface.DEFAULT_BOLD
            },
        )

        if (detail.title.isNotEmpty()) {
            card.addView(
                TextView(this).apply {
                    text = getString(R.string.block_by, detail.title)
                    setTextColor(MUTED)
                    setTextSize(TypedValue.COMPLEX_UNIT_SP, 13f)
                    gravity = Gravity.CENTER
                    setPadding(0, dp(6), 0, 0)
                },
            )
        }

        val status = detail.status.ifEmpty { getString(R.string.block_default_reason) }
        card.addView(
            TextView(this).apply {
                text = status
                setTextColor(Color.WHITE)
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 16f)
                gravity = Gravity.CENTER
                setLineSpacing(dp(4).toFloat(), 1f)
                setPadding(dp(4), dp(18), dp(4), 0)
            },
        )

        if (detail.progressPercent >= 0) {
            card.addView(progressBar(detail.progressPercent, dp(6), dp(18)))
            card.addView(
                TextView(this).apply {
                    text = getString(R.string.block_progress, detail.progressPercent)
                    setTextColor(ACCENT)
                    setTextSize(TypedValue.COMPLEX_UNIT_SP, 12f)
                    gravity = Gravity.CENTER
                    setPadding(0, dp(8), 0, 0)
                },
            )
        }

        if (unlockAt > 0) {
            countdown = TextView(this).apply {
                setTextColor(ACCENT)
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 15f)
                gravity = Gravity.CENTER
                setPadding(0, dp(16), 0, 0)
            }
            card.addView(countdown)
        }

        card.addView(
            Button(this).apply {
                text = getString(R.string.block_go_home)
                setTextColor(Color.WHITE)
                isAllCaps = false
                background = GradientDrawable().apply {
                    cornerRadius = dp(18).toFloat()
                    setColor(RAISED)
                }
                setOnClickListener { goHome() }
                layoutParams = LinearLayout.LayoutParams(
                    LinearLayout.LayoutParams.MATCH_PARENT,
                    dp(50),
                ).apply { topMargin = dp(26) }
            },
        )

        root.addView(card)
        return root
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
    private fun renderCountdown(): Boolean {
        val view = countdown ?: return false
        val remaining = unlockAt - System.currentTimeMillis()

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
        super.onPause()
        finish()
    }

    companion object {
        const val EXTRA_PACKAGE = "package"

        /** Package name for an app block, or the domain for a site block. */
        const val EXTRA_DETAIL_KEY = "detailKey"

        private val BACKGROUND = Color.parseColor("#0B0B0D")
        private val CARD = Color.parseColor("#161719")
        private val RAISED = Color.parseColor("#25262A")
        private val MUTED = Color.parseColor("#9A9AA0")
        private val ACCENT = Color.parseColor("#32D74B")
    }
}
