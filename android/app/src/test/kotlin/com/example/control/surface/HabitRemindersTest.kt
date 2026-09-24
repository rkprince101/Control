package com.example.control.surface

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import java.util.Calendar
import java.util.TimeZone

class HabitRemindersTest {
    private val zone = TimeZone.getTimeZone("Europe/Tallinn")

    private fun at(year: Int, month: Int, day: Int, hour: Int, minute: Int): Long =
        Calendar.getInstance(zone).apply {
            clear()
            set(year, month - 1, day, hour, minute, 0)
        }.timeInMillis

    @Test
    fun `fires later today when the time is still ahead`() {
        // Wednesday 23 September 2026, 08:00.
        val now = at(2026, 9, 23, 8, 0)
        assertEquals(at(2026, 9, 23, 9, 30), HabitReminders.nextTrigger(9 * 60 + 30, (1..7).toSet(), now, zone))
    }

    @Test
    fun `rolls to tomorrow once today's time has passed`() {
        val now = at(2026, 9, 23, 9, 30)
        assertEquals(at(2026, 9, 24, 9, 30), HabitReminders.nextTrigger(9 * 60 + 30, (1..7).toSet(), now, zone))
    }

    @Test
    fun `skips to the next due weekday`() {
        // Wednesday evening, due Monday only.
        val now = at(2026, 9, 23, 20, 0)
        assertEquals(at(2026, 9, 28, 7, 0), HabitReminders.nextTrigger(7 * 60, setOf(1), now, zone))
    }

    @Test
    fun `keeps local clock time across a daylight saving change`() {
        // Clocks go back overnight into Sunday 25 October 2026 in Tallinn.
        val now = at(2026, 10, 24, 12, 0)
        val next = HabitReminders.nextTrigger(9 * 60, setOf(7), now, zone)!!
        val fired = Calendar.getInstance(zone).apply { timeInMillis = next }
        assertEquals(25, fired.get(Calendar.DAY_OF_MONTH))
        assertEquals(9, fired.get(Calendar.HOUR_OF_DAY))
        assertEquals(0, fired.get(Calendar.MINUTE))
    }

    @Test
    fun `no days means no alarm`() {
        assertNull(HabitReminders.nextTrigger(9 * 60, emptySet(), at(2026, 9, 23, 8, 0), zone))
        assertNull(HabitReminders.nextTrigger(24 * 60, setOf(1), at(2026, 9, 23, 8, 0), zone))
    }

    @Test
    fun `weekdays and day keys match the Dart side`() {
        val wednesday = Calendar.getInstance(zone).apply { timeInMillis = at(2026, 9, 23, 8, 0) }
        assertEquals(3, HabitReminders.isoWeekday(wednesday))
        assertEquals(20260923, HabitReminders.dayKey(wednesday))
        val sunday = Calendar.getInstance(zone).apply { timeInMillis = at(2026, 9, 27, 8, 0) }
        assertEquals(7, HabitReminders.isoWeekday(sunday))
    }

    @Test
    fun `channel maps and stored json round trip`() {
        val reminder = HabitReminder.fromMap(
            mapOf(
                "id" to "water@540",
                "habitId" to "water",
                "title" to "Drink water",
                "body" to "8 glasses today.",
                "minute" to 540L,
                "weekdays" to listOf(1, 3, 5),
                "doneDay" to 20260923,
            ),
        )!!
        assertEquals(setOf(1, 3, 5), reminder.weekdays)
        assertEquals(540, reminder.minute)
        assertEquals(reminder, HabitReminder.fromJson(reminder.toJson()))
        assertNull(HabitReminder.fromMap(mapOf("id" to "x")))
    }
}
