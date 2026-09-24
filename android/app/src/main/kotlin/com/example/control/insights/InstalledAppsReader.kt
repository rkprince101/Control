package com.example.control.insights

import android.content.Context
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.BitmapDrawable
import android.graphics.drawable.Drawable
import java.io.ByteArrayOutputStream

data class InstalledApp(
    val packageName: String,
    val label: String,
    val isSystem: Boolean,
    val categories: List<String> = emptyList(),
) {
    fun toMap(): Map<String, Any?> = mapOf(
        "package" to packageName,
        "label" to label,
        "isSystem" to isSystem,
        "categories" to categories,
    )
}

/**
 * Feeds the app picker.
 *
 * Only launchable apps are listed, resolved through a LAUNCHER query declared in
 * the manifest. That keeps the app off the QUERY_ALL_PACKAGES permission, which
 * Play grants only for a narrow set of use cases and reviews harshly.
 */
class InstalledAppsReader(private val context: Context) {
    private val categories = AppCategoryResolver(context)

    fun launchable(includeCategories: Boolean = true): List<InstalledApp> {
        val manager = context.packageManager
        val intent = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)

        return manager.queryIntentActivities(intent, 0)
            .asSequence()
            .mapNotNull { it.activityInfo?.applicationInfo }
            .distinctBy { it.packageName }
            .filter { it.packageName != context.packageName }
            .map {
                InstalledApp(
                    packageName = it.packageName,
                    label = manager.getApplicationLabel(it).toString(),
                    isSystem = it.flags and ApplicationInfo.FLAG_SYSTEM != 0,
                    categories = if (includeCategories) categories.categories(it.packageName).toList() else emptyList(),
                )
            }
            .sortedBy { it.label.lowercase() }
            .toList()
    }

    /**
     * Package to label for everything that should appear on Insights.
     *
     * The picker excludes Control, because blocking Control with Control is not
     * a thing, but Insights must include it: leaving out the app whose screen
     * you are reading makes the numbers look wrong for no reason.
     */
    fun visibleForUsage(): Map<String, String> {
        val apps = launchable(includeCategories = false).associate { it.packageName to it.label }
        val self = runCatching {
            val info = context.packageManager.getApplicationInfo(context.packageName, 0)
            context.packageName to
                context.packageManager.getApplicationLabel(info).toString()
        }.getOrNull()

        return if (self == null) apps else apps + self
    }

    /**
     * PNG bytes for one icon, fetched on demand. Returned per app rather than
     * with the list: a few hundred decoded icons is tens of megabytes crossing
     * the channel at once.
     */
    fun iconPng(packageName: String): ByteArray? = runCatching {
        val drawable = context.packageManager.getApplicationIcon(packageName)
        drawable.toBitmap().toPngBytes()
    }.getOrNull()

    private fun Drawable.toBitmap(): Bitmap {
        if (this is BitmapDrawable && bitmap != null) return bitmap

        // Adaptive icons report no intrinsic size until they are drawn.
        val width = intrinsicWidth.takeIf { it > 0 } ?: ICON_FALLBACK_PX
        val height = intrinsicHeight.takeIf { it > 0 } ?: ICON_FALLBACK_PX
        val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        setBounds(0, 0, canvas.width, canvas.height)
        draw(canvas)
        return bitmap
    }

    private fun Bitmap.toPngBytes(): ByteArray = ByteArrayOutputStream().use { stream ->
        compress(Bitmap.CompressFormat.PNG, 100, stream)
        stream.toByteArray()
    }

    private companion object {
        const val ICON_FALLBACK_PX = 108
    }
}
