package com.rkprince.control.insights

import android.Manifest
import android.annotation.SuppressLint
import android.content.Context
import android.content.pm.PackageManager
import android.location.Location
import android.location.LocationManager
import android.os.Build
import android.os.CancellationSignal
import android.os.Handler
import android.os.Looper
import android.os.SystemClock

/**
 * A single location fix, taken only when the user asks for one.
 *
 * Deliberately not a geofence and not a background subscription. A place
 * condition is a check-in: the user is standing there with the phone in hand,
 * so one foreground fix is all that is needed. That keeps the app off
 * background location, which is the permission Play reviews hardest and the one
 * that costs the most battery.
 *
 * Every provider that is switched on is asked at once and the most accurate
 * fresh answer wins, inside a hard time limit. Asking GPS alone used to leave
 * a check-in indoors spinning for half a minute, and then fall back to
 * whatever fix the phone last had, however old: a fix from yesterday at the
 * gym is not proof of being at the gym now.
 */
class LocationReader(private val context: Context) {

    /** A fix and what is known about how far to trust it. */
    data class Fix(val location: Location, val ageMillis: Long, val mock: Boolean)

    fun hasPermission(): Boolean =
        context.checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) ==
            PackageManager.PERMISSION_GRANTED

    /** Android 12 lets people grant approximate location only; check-ins need precise. */
    fun hasApproximateOnly(): Boolean =
        !hasPermission() &&
            context.checkSelfPermission(Manifest.permission.ACCESS_COARSE_LOCATION) ==
            PackageManager.PERMISSION_GRANTED

    fun isEnabled(): Boolean {
        val manager = manager() ?: return false
        return providers(manager).isNotEmpty()
    }

    /**
     * Asks every enabled provider for a current fix and reports the best one,
     * or null if none arrives fresh within [FIX_TIMEOUT_MS].
     *
     * Reports the accuracy and whether the fix came from a mock provider rather
     * than hiding either: the rule refuses a check-in whose error circle is
     * not fully inside the zone, and a faked position is no check-in at all.
     */
    // The permission is checked on the first line, and every provider call is
    // wrapped so a revoked permission surfaces as no fix rather than a crash.
    @SuppressLint("MissingPermission")
    fun current(onResult: (Fix?) -> Unit) {
        val manager = manager()
        if (!hasPermission() || manager == null) {
            onResult(null)
            return
        }
        val providers = providers(manager)
        if (providers.isEmpty()) {
            onResult(null)
            return
        }

        val handler = Handler(Looper.getMainLooper())
        val fixes = mutableListOf<Location>()
        val cancels = mutableListOf<CancellationSignal>()
        var pending = providers.size
        var settled = false

        fun finish() {
            if (settled) return
            settled = true
            handler.removeCallbacksAndMessages(null)
            cancels.forEach { runCatching { it.cancel() } }
            val best = fixes.filter { ageOf(it) <= MAX_AGE_MS }.minByOrNull { it.accuracy }
                ?: lastKnown(manager)?.takeIf { ageOf(it) <= MAX_AGE_MS }
            onResult(best?.let { Fix(it, ageOf(it), isMock(it)) })
        }

        fun accept(location: Location?) {
            if (settled) return
            if (location != null) fixes.add(location)
            pending--
            // A tight fix is as good as it gets; no reason to keep someone waiting.
            if (pending <= 0 || (location != null && location.accuracy <= GOOD_ENOUGH_METERS)) {
                finish()
            }
        }

        for (provider in providers) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                val cancel = CancellationSignal().also { cancels.add(it) }
                runCatching {
                    manager.getCurrentLocation(provider, cancel, context.mainExecutor) { accept(it) }
                }.onFailure { accept(null) }
            } else {
                requestOnce(manager, provider, handler) { accept(it) }
            }
        }
        handler.postDelayed({ finish() }, FIX_TIMEOUT_MS)
    }

    /** Below API 30 there is no one-shot call: subscribe, take the first fix, unsubscribe. */
    @SuppressLint("MissingPermission")
    @Suppress("DEPRECATION")
    private fun requestOnce(
        manager: LocationManager,
        provider: String,
        handler: Handler,
        onFix: (Location?) -> Unit,
    ) {
        var done = false
        val listener = object : android.location.LocationListener {
            override fun onLocationChanged(location: Location) {
                if (done) return
                done = true
                manager.removeUpdates(this)
                onFix(location)
            }

            override fun onProviderEnabled(provider: String) = Unit
            override fun onProviderDisabled(provider: String) = Unit
        }
        runCatching {
            manager.requestLocationUpdates(provider, 0L, 0f, listener, Looper.getMainLooper())
        }.onFailure {
            done = true
            onFix(null)
            return
        }
        handler.postDelayed({
            if (done) return@postDelayed
            done = true
            manager.removeUpdates(listener)
        }, FIX_TIMEOUT_MS)
    }

    private fun providers(manager: LocationManager): List<String> {
        val candidates = buildList {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) add(LocationManager.FUSED_PROVIDER)
            add(LocationManager.GPS_PROVIDER)
            add(LocationManager.NETWORK_PROVIDER)
        }
        return candidates.filter { provider ->
            runCatching { manager.isProviderEnabled(provider) }.getOrDefault(false)
        }
    }

    @SuppressLint("MissingPermission")
    private fun lastKnown(manager: LocationManager): Location? = runCatching {
        providers(manager)
            .mapNotNull { manager.getLastKnownLocation(it) }
            .minByOrNull { ageOf(it) }
    }.getOrNull()

    private fun ageOf(location: Location): Long =
        (SystemClock.elapsedRealtimeNanos() - location.elapsedRealtimeNanos) / 1_000_000L

    @Suppress("DEPRECATION")
    private fun isMock(location: Location): Boolean =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) location.isMock
        else location.isFromMockProvider

    private fun manager() =
        context.getSystemService(Context.LOCATION_SERVICE) as? LocationManager

    private companion object {
        const val FIX_TIMEOUT_MS = 12_000L

        /** Older than this, a fix says where the phone was, not where it is. */
        const val MAX_AGE_MS = 120_000L

        const val GOOD_ENOUGH_METERS = 20f
    }
}
