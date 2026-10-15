package com.rkprince.control.enforcement

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
import android.text.InputFilter
import android.text.InputType
import android.window.OnBackInvokedDispatcher
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.view.WindowInsets
import android.view.inputmethod.InputMethodManager
import android.widget.Button
import android.widget.EditText
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.ProgressBar
import android.widget.ScrollView
import android.widget.TextView
import android.widget.Toast
import com.rkprince.control.EdgeToEdge
import com.rkprince.control.R
import com.rkprince.control.insights.AppCategoryResolver
import com.rkprince.control.thoughts.ThoughtCodec
import com.rkprince.control.thoughts.ThoughtStore
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
 *
 * It also takes the reason the app was opened. "Park a thought" writes down
 * what the user came for, so the urge has somewhere to go that is not a way
 * around the block, and it waits in Control's Thoughts page until the app
 * opens again. Nothing typed is lost: leaving the screen any way at all keeps
 * whatever is in the box.
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

    /** What the block is on right now: the package, or the site's domain. */
    private var currentTarget = ""

    private lateinit var scroll: ScrollView
    private lateinit var cardHolder: FrameLayout
    private lateinit var parkPanel: LinearLayout
    private var parkField: EditText? = null
    private var composing = false
    private var draft = ""

    private val tick = object : Runnable {
        override fun run() {
            if (!refreshBlock()) return
            handler.postDelayed(this, 1000L)
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Edge to edge over a dark screen: light bar icons, and the layout
        // keeps its card clear of the bars itself.
        EdgeToEdge.apply(window, darkContent = false)

        blockedPackage = intent.getStringExtra(EXTRA_PACKAGE).orEmpty()
        detailKey = intent.getStringExtra(EXTRA_DETAIL_KEY) ?: blockedPackage
        setContentView(buildShell())
        if (!refreshBlock()) return
        renderParkPanel()
        handler.postDelayed(tick, 1000L)

        // Android 13 introduced predictive back, and onBackPressed stops being
        // called once an app opts in. Registering here keeps back behaving like
        // Home on new releases as well as old ones.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            onBackInvokedDispatcher.registerOnBackInvokedCallback(
                OnBackInvokedDispatcher.PRIORITY_DEFAULT,
            ) { onBack() }
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
        val now = EnforcementClock.now(this)
        val plan = StepUnlocks.apply(this, planStore.read(), now)
        val tokens = if (plan.rules?.any { it.categories.isNotEmpty() } == true) {
            categories.categories(blockedPackage)
        } else emptySet()
        val appBlocked = plan.blocks(blockedPackage, tokens, now)
        val domain = if (detailKey != blockedPackage) {
            WebRules.matches(detailKey, plan.effectiveDomains(now))
        } else null
        if (!appBlocked && domain == null) {
            // Mid-sentence, the block lifting is no reason to throw the words
            // away: the screen stays until the thought is parked or dropped.
            if (composing) return true
            finish()
            return false
        }
        currentTarget = if (appBlocked) blockedPackage else domain!!
        val detail = plan.detailFor(
            if (appBlocked) blockedPackage else domain!!,
            if (appBlocked) tokens else emptySet(),
            now,
        )
        if (detail != currentDetail) {
            currentDetail = detail
            unlockAt = detail.unlockAt
            countdown = null
            // Only the card is rebuilt; the parking box below keeps its text.
            cardHolder.removeAllViews()
            cardHolder.addView(buildCard(blockedPackage, detail))
        }
        renderCountdown(now)
        return true
    }

    private fun dp(value: Int) = (value * resources.displayMetrics.density).toInt()

    /**
     * Built once: the background runs under the system bars, and the content
     * is padded clear of them and of the keyboard. The scroll view shrinks as
     * the keyboard opens, which is what keeps the parking box in sight.
     */
    private fun buildShell(): View {
        cardHolder = FrameLayout(this)
        parkPanel = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT,
            ).apply { topMargin = dp(12) }
        }
        val column = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            setPadding(dp(20), dp(24), dp(20), dp(24))
            addView(cardHolder)
            addView(parkPanel)
        }
        scroll = ScrollView(this).apply {
            isFillViewport = true
            addView(column)
        }
        return FrameLayout(this).apply {
            setBackgroundColor(BACKGROUND)
            addView(scroll)
            setOnApplyWindowInsetsListener { view, insets ->
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                    val bars = insets.getInsets(
                        WindowInsets.Type.systemBars() or WindowInsets.Type.displayCutout(),
                    )
                    val ime = insets.getInsets(WindowInsets.Type.ime())
                    view.setPadding(bars.left, bars.top, bars.right, maxOf(bars.bottom, ime.bottom))
                    if (ime.bottom > 0) revealComposer()
                } else {
                    @Suppress("DEPRECATION")
                    view.setPadding(
                        insets.systemWindowInsetLeft,
                        insets.systemWindowInsetTop,
                        insets.systemWindowInsetRight,
                        insets.systemWindowInsetBottom,
                    )
                    revealComposer()
                }
                insets
            }
        }
    }

    private fun buildCard(blockedPackage: String, detail: BlockDetail): ViewGroup {
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
        return card
    }

    // Park a thought ----------------------------------------------------------

    /** The site's domain for a site block, the app's name otherwise. */
    private fun subject(): String =
        if (currentTarget.isNotEmpty() && currentTarget != blockedPackage) currentTarget
        else labelFor(blockedPackage)

    /** Thoughts are kept in credential storage, shut until first unlock. */
    private fun canPark(): Boolean =
        getSystemService(UserManager::class.java)?.isUserUnlocked == true

    private fun renderParkPanel() {
        parkPanel.removeAllViews()
        parkField = null
        if (!canPark()) return
        if (!composing) {
            parkPanel.addView(
                outlinedButton(
                    getString(if (draft.isBlank()) R.string.park_button else R.string.park_resume),
                ) { openComposer() },
            )
            return
        }

        val box = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(20), dp(20), dp(20), dp(16))
            background = GradientDrawable().apply {
                cornerRadius = dp(28).toFloat()
                setColor(CARD)
            }
        }
        box.addView(
            TextView(this).apply {
                text = getString(R.string.park_prompt, subject())
                setTextColor(FOREGROUND)
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 18f)
                typeface = android.graphics.Typeface.DEFAULT_BOLD
            },
        )
        val field = EditText(this).apply {
            setText(draft)
            setSelection(draft.length)
            hint = getString(R.string.park_hint)
            contentDescription = getString(R.string.park_prompt, subject())
            setTextColor(FOREGROUND)
            setHintTextColor(MUTED)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 16f)
            inputType = InputType.TYPE_CLASS_TEXT or
                InputType.TYPE_TEXT_FLAG_MULTI_LINE or
                InputType.TYPE_TEXT_FLAG_CAP_SENTENCES
            filters = arrayOf(InputFilter.LengthFilter(ThoughtCodec.MAX_LENGTH))
            minLines = 3
            maxLines = 6
            gravity = Gravity.TOP or Gravity.START
            setPadding(dp(14), dp(12), dp(14), dp(12))
            background = GradientDrawable().apply {
                cornerRadius = dp(16).toFloat()
                setColor(RAISED)
            }
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT,
            ).apply { topMargin = dp(14) }
        }
        parkField = field
        box.addView(field)
        box.addView(
            TextView(this).apply {
                text = getString(R.string.park_helper, subject())
                setTextColor(MUTED)
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 13f)
                setLineSpacing(dp(2).toFloat(), 1f)
                setPadding(dp(4), dp(10), dp(4), 0)
            },
        )
        val actions = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.END
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT,
            ).apply { topMargin = dp(14) }
        }
        actions.addView(
            Button(this).apply {
                text = getString(R.string.park_cancel)
                setTextColor(MUTED)
                isAllCaps = false
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 15f)
                minHeight = dp(48)
                minimumHeight = dp(48)
                background = null
                setOnClickListener {
                    draft = ""
                    closeComposer()
                }
            },
        )
        actions.addView(
            Button(this).apply {
                text = getString(R.string.park_save)
                setTextColor(BACKGROUND)
                isAllCaps = false
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 15f)
                minHeight = dp(48)
                minimumHeight = dp(48)
                setPadding(dp(24), 0, dp(24), 0)
                background = GradientDrawable().apply {
                    cornerRadius = dp(24).toFloat()
                    setColor(ACCENT)
                }
                setOnClickListener { park() }
                layoutParams = LinearLayout.LayoutParams(
                    LinearLayout.LayoutParams.WRAP_CONTENT,
                    LinearLayout.LayoutParams.WRAP_CONTENT,
                ).apply { marginStart = dp(8) }
            },
        )
        box.addView(actions)
        parkPanel.addView(box)

        field.requestFocus()
        field.post {
            getSystemService(InputMethodManager::class.java)
                ?.showSoftInput(field, InputMethodManager.SHOW_IMPLICIT)
        }
    }

    /**
     * With the keyboard up, scrolls the whole box into view, Park it
     * included. Keeping only the focused field visible left the buttons
     * hidden under the keyboard.
     */
    private fun revealComposer() {
        if (!composing) return
        scroll.post { scroll.smoothScrollTo(0, parkPanel.bottom) }
    }

    private fun outlinedButton(label: String, onClick: () -> Unit) = Button(this).apply {
        text = label
        setTextColor(ACCENT)
        setTextSize(TypedValue.COMPLEX_UNIT_SP, 16f)
        isAllCaps = false
        minHeight = dp(48)
        minimumHeight = dp(48)
        setPadding(dp(20), dp(12), dp(20), dp(12))
        background = GradientDrawable().apply {
            cornerRadius = dp(24).toFloat()
            setColor(Color.TRANSPARENT)
            setStroke(dp(1), ACCENT)
        }
        setOnClickListener { onClick() }
        layoutParams = LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT,
            LinearLayout.LayoutParams.WRAP_CONTENT,
        )
    }

    private fun openComposer() {
        composing = true
        renderParkPanel()
    }

    /** Back to the plain block screen, with whatever [draft] holds now. */
    private fun closeComposer() {
        parkField?.let { field ->
            getSystemService(InputMethodManager::class.java)
                ?.hideSoftInputFromWindow(field.windowToken, 0)
        }
        composing = false
        renderParkPanel()
        // The block may have lifted while the box was open.
        refreshBlock()
    }

    private fun park() {
        val text = parkField?.text?.toString().orEmpty()
        if (text.isBlank()) {
            draft = ""
            closeComposer()
            return
        }
        draft = text
        if (!saveDraft()) return
        Toast.makeText(this, getString(R.string.park_saved), Toast.LENGTH_LONG).show()
        goHome()
    }

    /**
     * Writes whatever is in the box, once. Park it, Home and leaving the
     * screen all call this in turn, so a saved draft empties the box too:
     * reading the box again must not park the same words twice.
     */
    private fun saveDraft(): Boolean {
        parkField?.let { draft = it.text.toString() }
        if (draft.isBlank() || !canPark()) return true
        val saved = runCatching {
            ThoughtStore(this).add(
                text = draft,
                packageName = blockedPackage,
                target = currentTarget.ifEmpty { detailKey },
                label = subject(),
                blockTitle = currentDetail?.title.orEmpty(),
            )
        }.isSuccess
        if (saved) {
            draft = ""
            parkField?.setText("")
        }
        return saved
    }

    private fun onBack() {
        if (composing) {
            // Back from the box returns to the block screen, words kept.
            draft = parkField?.text?.toString().orEmpty()
            closeComposer()
            return
        }
        goHome()
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
        saveDraft()
        composing = false
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
        onBack()
    }

    /**
     * Anything that takes focus away closes this screen, so it never lingers
     * over an unrelated app.
     */
    override fun onPause() {
        handler.removeCallbacks(tick)
        // Leaving any way at all keeps what was typed.
        saveDraft()
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
