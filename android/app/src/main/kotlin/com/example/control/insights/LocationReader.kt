package com.example.control.insights

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

/**
 * A single location fix, taken only when the user asks for one.
 *
 * Deliberately not a geofence and not a background subscription. A place
 * condition is a check-in: the user is standing there with the phone in hand,
 * so one foreground fix is all that is needed. That keeps the app off
 * background location, which is the permission Play reviews hardest and the one
 * that costs the most battery.
 */
class LocationReader(private val context: Context) {

    fun hasPermission(): Boolean =
        context.checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) ==
            PackageManager.PERMISSION_GRANTED

    fun isEnabled(): Boolean {
        val manager = manager() ?: return false
        return manager.isProviderEnabled(LocationManager.GPS_PROVIDER) ||
            manager.isProviderEnabled(LocationManager.NETWORK_PROVIDER)
    }

    /**
     * Asks for a current fix, falling back to the last known one.
     *
     * Reports the accuracy alongside the point rather than hiding it: the rule
     * engine refuses a check-in whose error circle is not fully inside the
     * zone, and it can only do that if this is honest about how vague the fix
     * was.
     */
    // Guarded twice over: the permission is checked on the first line, and both
    // provider calls are wrapped so a revoked permission surfaces as no fix
    // rather than as a crash. Lint cannot follow either.
    @SuppressLint("MissingPermission")
    fun current(onResult: (Location?) -> Unit) {
        if (!hasPermission()) {
            onResult(null)
            return
        }
        val manager = manager()
        if (manager == null) {
            onResult(null)
            return
        }

        val provider = when {
            manager.isProviderEnabled(LocationManager.GPS_PROVIDER) ->
                LocationManager.GPS_PROVIDER

            manager.isProviderEnabled(LocationManager.NETWORK_PROVIDER) ->
                LocationManager.NETWORK_PROVIDER

            else -> null
        }

        if (provider == null) {
            onResult(null)
            return
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            runCatching {
                manager.getCurrentLocation(
                    provider,
                    CancellationSignal(),
                    context.mainExecutor,
                ) { location -> onResult(location ?: lastKnown(manager)) }
            }.onFailure { onResult(lastKnown(manager)) }
            return
        }

        // Below API 30 there is no one-shot call, so subscribe and unsubscribe
        // on the first fix, with a timeout so a cold GPS never hangs the UI.
        @Suppress("DEPRECATION")
        run {
            val handler = Handler(Looper.getMainLooper())
            var settled = false

            val listener = object : android.location.LocationListener {
                override fun onLocationChanged(location: Location) {
                    if (settled) return
                    settled = true
                    manager.removeUpdates(this)
                    onResult(location)
                }

                override fun onProviderEnabled(provider: String) = Unit
                override fun onProviderDisabled(provider: String) = Unit
            }

            runCatching {
                manager.requestLocationUpdates(provider, 0L, 0f, listener, Looper.getMainLooper())
            }.onFailure {
                onResult(lastKnown(manager))
                return
            }

            handler.postDelayed({
                if (settled) return@postDelayed
                settled = true
                manager.removeUpdates(listener)
                onResult(lastKnown(manager))
            }, FIX_TIMEOUT_MS)
        }
    }

    @Suppress("MissingPermission")
    private fun lastKnown(manager: LocationManager): Location? = runCatching {
        listOf(LocationManager.GPS_PROVIDER, LocationManager.NETWORK_PROVIDER)
            .mapNotNull { manager.getLastKnownLocation(it) }
            .maxByOrNull { it.time }
    }.getOrNull()

    private fun manager() =
        context.getSystemService(Context.LOCATION_SERVICE) as? LocationManager

    private companion object {
        const val FIX_TIMEOUT_MS = 8000L
    }
}
