package com.rkprince.control.enforcement

import android.content.Context
import android.content.SharedPreferences
import android.os.UserManager

/** Only native rules, the guard flag and the clock belong here, never passwords
 * or the Flutter habit/history file. Device-protected storage is readable before
 * the first unlock after boot, unlike credential-protected app storage. */
internal object EnforcementStorage {
    private val migrated = mutableSetOf<String>()
    var generation = 0
        private set

    @Synchronized
    fun preferences(context: Context, name: String): SharedPreferences {
        val app = context.applicationContext
        val device = app.createDeviceProtectedStorageContext()
        val users = app.getSystemService(Context.USER_SERVICE) as UserManager
        if (users.isUserUnlocked && name !in migrated) {
            // The application retains its default credential-protected context;
            // only these selected native stores opt into device protection.
            check(device.moveSharedPreferencesFrom(app, name)) {
                "Could not migrate enforcement preferences: $name"
            }
            migrated.add(name)
            generation++
        }
        return device.getSharedPreferences(name, Context.MODE_PRIVATE)
    }
}
