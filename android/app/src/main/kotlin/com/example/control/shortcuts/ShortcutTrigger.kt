package com.example.control.shortcuts

import android.app.Activity
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.widget.Toast

/**
 * Ways the outside world can fire a habit channel.
 *
 * Both entry points are exported, which looks alarming and is not: the only
 * thing firing a channel can do is credit the user with a habit they claim to
 * have done. There is no security boundary to defend, because the person who
 * would abuse it is the same person who set the rule. What matters is that the
 * trigger is easy to attach to something physical — a tag on the gym bag, a
 * button on the fridge — since that friction is the entire mechanism.
 */
object ShortcutContract {
    const val ACTION = "com.example.control.action.SHORTCUT"
    const val EXTRA_CHANNEL = "channel"

    /** `control://shortcut/<channel>` or `control://shortcut?channel=<channel>`. */
    const val SCHEME = "control"
    const val HOST = "shortcut"

    fun channelFrom(intent: Intent): String? {
        intent.getStringExtra(EXTRA_CHANNEL)?.let { return it }

        val data = intent.data ?: return null
        if (data.scheme != SCHEME || data.host != HOST) return null
        return data.getQueryParameter(EXTRA_CHANNEL)
            ?: data.pathSegments.firstOrNull()
    }

    fun confirm(context: Context, channel: String, count: Int) {
        Toast.makeText(
            context,
            context.getString(
                com.example.control.R.string.shortcut_fired,
                channel,
                count,
            ),
            Toast.LENGTH_SHORT,
        ).show()
    }
}

/** Fired by automation apps: Tasker, MacroDroid, Automate, `adb shell am broadcast`. */
class ShortcutReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        val channel = ShortcutContract.channelFrom(intent) ?: return
        val count = ShortcutStore(context).fire(channel)
        ShortcutContract.confirm(context, channel, count)
    }
}

/**
 * Fired by anything that opens a link: NFC tags, QR codes, home-screen
 * shortcuts, other apps. Shows a toast and gets out of the way immediately, so
 * tapping a tag never pulls the user into an app.
 */
class ShortcutTriggerActivity : Activity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        val channel = ShortcutContract.channelFrom(intent)
        if (channel != null) {
            val count = ShortcutStore(this).fire(channel)
            ShortcutContract.confirm(this, channel, count)
        }
        finish()
    }
}
