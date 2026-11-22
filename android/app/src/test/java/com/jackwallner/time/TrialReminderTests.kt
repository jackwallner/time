package com.jackwallner.time

import com.jackwallner.time.data.InMemoryStore
import com.jackwallner.time.data.TrialReminder
import java.time.Instant
import java.time.LocalDateTime
import java.time.ZoneId
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** iOS `NotificationPlanTests` trial reminder, and its remembered-and-cancelled behaviour (iOS commit ce74592). */
class TrialReminderTests {
    private val zone = ZoneId.of("America/Los_Angeles")

    private fun at(month: Int, day: Int, hour: Int, minute: Int = 0, in_: ZoneId = zone): Instant =
        LocalDateTime.of(2026, month, day, hour, minute).atZone(in_).toInstant()

    /** Lands two days before the end, in the morning, whatever hour the trial began. */
    @Test fun trialReminderIsTwoDaysBeforeTheEndAtTenInTheMorning() {
        val startedAt = at(9, 21, 2, 14)
        assertEquals(at(9, 26, 10), TrialReminder.reminderDate(7, startedAt, zone))
        assertEquals(at(9, 22, 10), TrialReminder.reminderDate(3, startedAt, zone))
        assertEquals(at(9, 22, 10), TrialReminder.reminderDate(1, startedAt, zone))
    }

    @Test fun trialReminderStaysAtTenAcrossDaylightSavingChanges() {
        // Fall back on 1 November 2026: 10 AM is PST by then.
        assertEquals(at(11, 4, 10), TrialReminder.reminderDate(7, at(10, 30, 2, 14), zone))
        // Spring forward on 14 March 2027: 10 AM is PDT by then.
        val spring = LocalDateTime.of(2027, 3, 15, 10, 0).atZone(zone).toInstant()
        assertEquals(spring, TrialReminder.reminderDate(7, LocalDateTime.of(2027, 3, 10, 23, 30).atZone(zone).toInstant(), zone))
    }

    @Test fun trialReminderFollowsTheDeviceZone() {
        val auckland = ZoneId.of("Pacific/Auckland")
        val startedAt = at(9, 21, 7, 0)
        // 7 AM on the 21st in Los Angeles is already the 22nd in Auckland.
        assertEquals(at(9, 26, 10), TrialReminder.reminderDate(7, startedAt, zone))
        assertEquals(at(9, 27, 10, in_ = auckland), TrialReminder.reminderDate(7, startedAt, auckland))
    }

    @Test fun theReminderIsRememberedUntilItFiresOrIsCancelled() {
        val defaults = InMemoryStore()
        val fireAt = at(9, 26, 10)
        assertNull(TrialReminder.pending(defaults, at(9, 21, 8)))
        TrialReminder.remember(defaults, fireAt, "$9.99/year")
        // Still there after the alarms were dropped by a reboot.
        assertEquals(fireAt to "$9.99/year", TrialReminder.pending(defaults, at(9, 25, 8)))
        assertNull(TrialReminder.pending(defaults, at(9, 26, 11)))
        assertTrue(TrialReminder.forget(defaults))
        assertNull(TrialReminder.pending(defaults, at(9, 21, 8)))
        assertFalse(TrialReminder.forget(defaults))
    }
}
