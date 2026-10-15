package com.rkprince.control.insights

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import androidx.health.connect.client.HealthConnectClient
import androidx.health.connect.client.HealthConnectFeatures
import androidx.health.connect.client.PermissionController
import androidx.health.connect.client.feature.ExperimentalMindfulnessSessionApi
import androidx.health.connect.client.permission.HealthPermission
import androidx.health.connect.client.records.ExerciseSessionRecord
import androidx.health.connect.client.records.MindfulnessSessionRecord
import androidx.health.connect.client.records.Record
import androidx.health.connect.client.request.ReadRecordsRequest
import androidx.health.connect.client.time.TimeRangeFilter
import java.time.Instant
import kotlin.reflect.KClass

/**
 * Workouts and mindfulness sessions other apps have written to Health Connect
 * (Mi Fitness, Google Fit, Samsung Health, Headspace and so on).
 *
 * Only session times are read: when one started and when it ended. Nothing
 * about heart rate, routes, calories or anything else, and only for today.
 *
 * Health Connect needs Android 8 (API 26); the app still runs on 7, where this
 * reports itself unavailable and the built-in timer is the only source.
 */
class HealthReader(context: Context) {

    private val context = context.applicationContext

    /** `available`, `updateRequired` (install or update the provider) or `unavailable`. */
    fun sdkStatus(): String {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return UNAVAILABLE
        return when (runCatching { HealthConnectClient.getSdkStatus(context) }.getOrNull()) {
            HealthConnectClient.SDK_AVAILABLE -> AVAILABLE
            HealthConnectClient.SDK_UNAVAILABLE_PROVIDER_UPDATE_REQUIRED -> UPDATE_REQUIRED
            else -> UNAVAILABLE
        }
    }

    private fun client(): HealthConnectClient? =
        if (sdkStatus() == AVAILABLE) {
            runCatching { HealthConnectClient.getOrCreate(context) }.getOrNull()
        } else null

    /**
     * Mindfulness sessions are newer than the rest of Health Connect; older
     * providers do not have them at all, and asking for the permission there
     * makes the whole request fail.
     */
    @OptIn(ExperimentalMindfulnessSessionApi::class)
    private fun mindfulnessSupported(client: HealthConnectClient): Boolean = runCatching {
        client.features.getFeatureStatus(HealthConnectFeatures.FEATURE_MINDFULNESS_SESSION) ==
            HealthConnectFeatures.FEATURE_STATUS_AVAILABLE
    }.getOrDefault(false)

    private fun permissionsFor(client: HealthConnectClient): Set<String> = buildSet {
        add(READ_EXERCISE)
        if (mindfulnessSupported(client)) add(READ_MINDFULNESS)
    }

    suspend fun status(): Map<String, Any> {
        val sdk = sdkStatus()
        val client = client() ?: return mapOf(
            "sdk" to sdk,
            "workout" to false,
            "mindful" to false,
            "mindfulSupported" to false,
        )
        val granted = runCatching { client.permissionController.getGrantedPermissions() }
            .getOrDefault(emptySet())
        val mindfulSupported = mindfulnessSupported(client)
        return mapOf(
            "sdk" to sdk,
            "workout" to (READ_EXERCISE in granted),
            "mindful" to (mindfulSupported && READ_MINDFULNESS in granted),
            "mindfulSupported" to mindfulSupported,
        )
    }

    /** The read permissions to ask for, or null when Health Connect is not there. */
    fun permissionsToRequest(): Set<String>? = client()?.let { permissionsFor(it) }

    /**
     * Health Connect's own page for Control's permissions, where they can be
     * granted after Android has stopped showing the prompt (Android 14+).
     */
    fun managePermissionsIntent(packageName: String): Intent =
        Intent("android.health.connect.action.MANAGE_HEALTH_PERMISSIONS")
            .putExtra(Intent.EXTRA_PACKAGE_NAME, packageName)

    /**
     * The permission screen before Android 14, where Health Connect is an app
     * and its permissions are granted through its own activity. From 14 they
     * are ordinary runtime permissions, and this contract's intent only works
     * inside a ComponentActivity; see [permissionsToRequest].
     */
    fun permissionIntent(): Intent? {
        val client = client() ?: return null
        return runCatching {
            PermissionController.createRequestPermissionResultContract()
                .createIntent(context, permissionsFor(client))
        }.getOrNull()
    }

    /**
     * Where to send someone whose Health Connect is missing or out of date: the
     * Play listing on Android 13 and below, where it is an app. From Android 14
     * it is part of the system, and its settings are the place to go instead.
     */
    fun setupIntent(): Intent =
        if (sdkStatus() == AVAILABLE) {
            Intent(HealthConnectClient.ACTION_HEALTH_CONNECT_SETTINGS)
        } else {
            Intent(
                Intent.ACTION_VIEW,
                Uri.parse("market://details?id=${PROVIDER_PACKAGE}&url=healthconnect%3A%2F%2Fonboarding"),
            ).setPackage("com.android.vending")
        }

    /**
     * Start and end of every workout and mindfulness session overlapping
     * [startMillis]..[endMillis], in epoch millis. Kinds without permission
     * come back empty rather than failing the whole read.
     */
    @OptIn(ExperimentalMindfulnessSessionApi::class)
    suspend fun sessions(startMillis: Long, endMillis: Long): Map<String, List<List<Long>>> {
        val client = client() ?: return mapOf("workout" to emptyList(), "mindful" to emptyList())
        val granted = runCatching { client.permissionController.getGrantedPermissions() }
            .getOrDefault(emptySet())
        val range = TimeRangeFilter.between(
            Instant.ofEpochMilli(startMillis),
            Instant.ofEpochMilli(endMillis),
        )
        val workouts = if (READ_EXERCISE in granted) {
            read(client, ExerciseSessionRecord::class, range) { it.startTime to it.endTime }
        } else emptyList()
        val mindful = if (mindfulnessSupported(client) &&
            READ_MINDFULNESS in granted
        ) {
            read(client, MindfulnessSessionRecord::class, range) { it.startTime to it.endTime }
        } else emptyList()
        return mapOf("workout" to workouts, "mindful" to mindful)
    }

    private suspend fun <T : Record> read(
        client: HealthConnectClient,
        type: KClass<T>,
        range: TimeRangeFilter,
        span: (T) -> Pair<Instant, Instant>,
    ): List<List<Long>> {
        val spans = mutableListOf<List<Long>>()
        var page: String? = null
        do {
            val response = client.readRecords(
                ReadRecordsRequest(
                    recordType = type,
                    timeRangeFilter = range,
                    pageSize = PAGE_SIZE,
                    pageToken = page,
                ),
            )
            response.records.forEach { record ->
                val (start, end) = span(record)
                if (end.isAfter(start)) spans.add(listOf(start.toEpochMilli(), end.toEpochMilli()))
            }
            page = response.pageToken
        } while (!page.isNullOrEmpty() && spans.size < MAX_SESSIONS)
        return spans
    }

    @OptIn(ExperimentalMindfulnessSessionApi::class)
    companion object {
        private val READ_EXERCISE = HealthPermission.getReadPermission(ExerciseSessionRecord::class)
        private val READ_MINDFULNESS = HealthPermission.getReadPermission(MindfulnessSessionRecord::class)

        /** Health Connect as an app, before Android 14 made it part of the system. */
        private const val PROVIDER_PACKAGE = "com.google.android.apps.healthdata"

        const val AVAILABLE = "available"
        const val UPDATE_REQUIRED = "updateRequired"
        const val UNAVAILABLE = "unavailable"
        private const val PAGE_SIZE = 200
        private const val MAX_SESSIONS = 1000
    }
}
