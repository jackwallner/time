package com.jackwallner.time

import com.jackwallner.time.data.ConversionDiagnostics
import com.jackwallner.time.data.InMemoryStore
import com.jackwallner.time.data.Plan
import com.jackwallner.time.data.PlanKind
import com.jackwallner.time.data.ReviewPromptTracker
import com.jackwallner.time.data.ShoesOnProduct
import com.jackwallner.time.data.StoreService
import com.jackwallner.time.model.DayChange
import com.jackwallner.time.model.Format
import com.jackwallner.time.model.Routine
import com.jackwallner.time.model.RoutineStep
import java.time.Instant
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.ZoneId
import java.util.Locale
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** One for one with iOS `DayChangeTests`. */
class DayChangeTests {
    private val zone = ZoneId.of("America/Los_Angeles")
    private fun day(day: Int): LocalDate = LocalDate.of(2026, 9, day)
    private fun date(day: Int, hour: Int = 0, minute: Int = 0): Instant = LocalDateTime.of(2026, 9, day, hour, minute).atZone(zone).toInstant()

    /** Weekdays at 8:15. The 21st is a Monday. */
    private val routine = Routine(name = "Weekday mornings", leaveHour = 8, leaveMinute = 15, weekdays = setOf(2, 3, 4, 5, 6), steps = listOf(RoutineStep(name = "Shower", guessMinutes = 10)))

    @Test fun skippingTomorrowMovesTheNextDepartureOn() {
        val skipping = routine.settingChange(DayChange(day(22), null), day(22))
        assertFalse(skipping.departs(day(22)))
        assertEquals(date(23, 8, 15), skipping.nextScheduledLeave(date(21, 9), zone))
    }

    @Test fun aOneOffTimeAppliesToThatDayOnly() {
        val changed = routine.settingChange(DayChange(day(22), 7 * 60 + 30), day(22))
        assertEquals(date(22, 7, 30), changed.leaveTime(day(22), zone))
        assertEquals(date(23, 8, 15), changed.leaveTime(day(23), zone))
    }

    @Test fun theUsualLeaveTimeIgnoresAOneOff() {
        val changed = routine.settingChange(DayChange(day(22), 7 * 60 + 30), day(22))
        assertEquals(date(22, 8, 15), changed.usualLeaveTime(day(22), zone))
    }

    @Test fun changesThatChangeNothingAreDropped() {
        val changed = routine
            .settingChange(DayChange(day(22), 8 * 60 + 15), day(22))
            // Saturday is not a routine day, so skipping it changes nothing either.
            .settingChange(DayChange(day(26), null), day(26))
        assertTrue(changed.changes.isEmpty())
    }

    @Test fun oneChangePerDayAndUndoClearsIt() {
        var changed = routine.settingChange(DayChange(day(22), null), day(22))
        changed = changed.settingChange(DayChange(day(22), 9 * 60), day(22))
        assertEquals(1, changed.changes.size)
        assertEquals(day(22), changed.changes.first().day)
        assertTrue(changed.settingChange(null, day(22)).changes.isEmpty())
    }

    @Test fun pastChangesArePruned() {
        val changed = routine.settingChange(DayChange(day(22), null), day(22)).settingChange(DayChange(day(24), null), day(24))
        assertEquals(listOf(day(24)), changed.pruningChanges(date(23, 6), zone).changes.map { it.day })
    }
}

/** One for one with iOS `PaywallFunnelTests`, plus the review tracker and paywall copy. */
class PaywallFunnelTests {
    private val defaults = InMemoryStore()
    private val diagnostics = ConversionDiagnostics(defaults)

    @Test fun countsPitchesPerSurfaceAndInTotal() {
        diagnostics.recordPitchView("shoeson_paywall")
        diagnostics.recordPitchView("shoeson_paywall")
        diagnostics.recordPitchView("shoeson_onboarding_trial")
        val attributes = diagnostics.subscriberAttributes
        assertEquals("3", attributes["pitch_views_total"])
        assertEquals("2", attributes["pitch_views_paywall"])
        assertEquals("onboarding_trial", attributes["pitch_last"])
    }

    @Test fun noAttributesBeforeAnyPitchIsSeen() {
        diagnostics.recordAppOpen()
        assertTrue(diagnostics.subscriberAttributes.isEmpty())
    }

    @Test fun recordsHowEarlyTheFirstPitchArrived() {
        diagnostics.recordAppOpen()
        diagnostics.recordAppOpen()
        diagnostics.recordPitchView("shoeson_paywall")
        val attributes = diagnostics.subscriberAttributes
        assertEquals("2", attributes["opens_before_first_pitch"])
        assertEquals("0", attributes["days_since_install"])
    }

    @Test fun theEarlinessPairIsFrozenOnTheFirstPitchOnly() {
        diagnostics.recordAppOpen()
        diagnostics.recordPitchView("shoeson_paywall")
        diagnostics.recordAppOpen()
        diagnostics.recordPitchView("shoeson_onboarding_trial")
        assertEquals("1", diagnostics.subscriberAttributes["opens_before_first_pitch"])
    }

    @Test fun anInstallThatPredatesThisCodeReportsNoAge() {
        diagnostics.recordPitchView("shoeson_paywall")
        assertNull(diagnostics.subscriberAttributes["days_since_install"])
        assertNotNull(diagnostics.subscriberAttributes["pitch_views_total"])
    }

    @Test fun conversionFreezesTheSurfaceAndCountAtTheMomentOfSale() {
        diagnostics.recordPitchView("shoeson_paywall")
        diagnostics.recordPitchView("shoeson_onboarding_trial")
        diagnostics.recordConversion("yearly", startedTrial = true, offeringID = "default")
        diagnostics.recordPitchView("shoeson_paywall")
        val attributes = diagnostics.subscriberAttributes
        assertEquals("onboarding_trial", attributes["converted_surface"])
        assertEquals("2", attributes["pitch_views_at_convert"])
        assertEquals("yearly", attributes["converted_plan"])
        assertEquals("true", attributes["converted_with_trial"])
        assertEquals("default", attributes["converted_offering"])
    }

    @Test fun onlyTheFirstConversionIsRecorded() {
        diagnostics.recordPitchView("shoeson_paywall")
        diagnostics.recordConversion("monthly", startedTrial = true)
        diagnostics.recordConversion("yearly", startedTrial = false)
        assertEquals("monthly", diagnostics.subscriberAttributes["converted_plan"])
        assertEquals("true", diagnostics.subscriberAttributes["converted_with_trial"])
    }

    @Test fun attributeKeysStayInsideRevenueCatsLimit() {
        diagnostics.recordPitchView("shoeson_" + "a".repeat(80))
        diagnostics.subscriberAttributes.keys.forEach { assertTrue("too long: $it", it.length <= 40) }
    }

    @Test fun noAttributeCarriesFreeText() {
        diagnostics.recordAppOpen()
        diagnostics.recordPitchView("shoeson_paywall")
        diagnostics.recordConversion("monthly", startedTrial = false)
        diagnostics.subscriberAttributes.forEach { (key, value) ->
            assertFalse("$key looks like free text: $value", value.contains(" "))
            assertTrue("$key is too long to be a label", value.length <= 64)
        }
    }

    @Test fun reviewIsAskedOnlyAfterThreeOnTimeDeparturesAndThenCoolsDown() {
        var now = Instant.parse("2026-09-21T15:00:00Z")
        val tracker = ReviewPromptTracker(defaults) { now }
        assertFalse(tracker.shouldAskAfterOnTimeDeparture(2))
        assertTrue(tracker.shouldAskAfterOnTimeDeparture(3))
        assertFalse("once a session", tracker.shouldAskAfterOnTimeDeparture(4))
        now = now.plusSeconds(30 * 86_400L)
        assertFalse("inside the 90 day cooldown", ReviewPromptTracker(defaults) { now }.isEligible(5))
        now = now.plusSeconds(61 * 86_400L)
        assertTrue(ReviewPromptTracker(defaults) { now }.isEligible(5))
    }

    @Test fun reviewerAccessOpensOnlyForTheRightCode() {
        val digest = java.security.MessageDigest.getInstance("SHA-256").digest("shoes-review".toByteArray()).joinToString("") { "%02x".format(it) }
        val access = com.jackwallner.time.data.ReviewAccess(defaults, digest)
        assertFalse(access.isGranted)
        assertFalse(access.activate("wrong"))
        assertFalse(access.isGranted)
        assertTrue(access.activate(" shoes-review "))
        assertTrue(com.jackwallner.time.data.ReviewAccess(defaults, digest).isGranted)
        // No digest configured: reviewer access is off entirely.
        assertFalse(com.jackwallner.time.data.ReviewAccess(InMemoryStore(), "").activate("shoes-review"))
    }

    @Test fun planCopyMatchesIos() {
        val yearly = Plan.fixtures.first { it.kind == PlanKind.YEARLY }
        val monthly = Plan.fixtures.first { it.kind == PlanKind.MONTHLY }
        assertEquals(ShoesOnProduct.YEARLY, yearly.productId)
        assertEquals("com.jackwallner.time.monthly", monthly.productId)
        assertEquals("$9.99 per year", yearly.billedLabel)
        assertEquals("$1.99 per month", monthly.billedLabel)
        assertEquals("7-day free trial", yearly.trialLabel)
        // $9.99 against 12 x $1.99 = $23.88.
        assertEquals("Save 58%", Plan.savingsBadge(yearly, monthly))
        assertNull(Plan.savingsBadge(yearly, null))
        assertEquals("pro", StoreService.ENTITLEMENT)
        assertEquals("default", StoreService.OFFERING_ID)
        assertEquals(
            "https://play.google.com/store/account/subscriptions?sku=com.jackwallner.time.yearly&package=com.jackwallner.time",
            StoreService.manageSubscriptionURL(ShoesOnProduct.YEARLY),
        )
    }
}

/** `Format` is shared copy on every screen; pin it to the iOS strings. */
class FormatTests {
    private val zone = ZoneId.of("America/Los_Angeles")

    @Test fun durations() {
        assertEquals("45 min", Format.duration(45))
        assertEquals("1 hr", Format.duration(60))
        assertEquals("1 hr 8 min", Format.duration(68))
    }

    @Test fun minutesRoundLikeSwift() {
        assertEquals(0, Format.minutes(0.0))
        assertEquals(1, Format.minutes(10.0))
        assertEquals(3, Format.minutes(150.0))
        assertEquals(1, Format.minutes(89.0))
        assertEquals(2, Format.minutes(95.0))
    }

    @Test fun relativeAndLateness() {
        val now = Instant.parse("2026-09-21T15:00:00Z")
        assertEquals("now", Format.relative(now.minusSeconds(30), now))
        assertEquals("in 42 min", Format.relative(now.plusSeconds(41 * 60 + 5), now))
        assertEquals("in 3 hr 5 min", Format.relative(now.plusSeconds(185 * 60L), now))
        assertEquals("On time", Format.lateness(40.0))
        assertEquals("2 min early", Format.lateness(-120.0))
        assertEquals("6 min late", Format.lateness(6 * 60.0))
    }

    @Test fun weekdaySets() {
        assertEquals("Every day", Format.weekdays((1..7).toSet()))
        assertEquals("Weekdays", Format.weekdays(setOf(2, 3, 4, 5, 6)))
        assertEquals("Weekends", Format.weekdays(setOf(1, 7)))
        assertEquals("No days set", Format.weekdays(emptySet()))
        assertEquals("Mon, Wed, Fri", Format.weekdays(setOf(2, 4, 6), Locale.US))
        assertEquals(listOf(1, 2, 3, 4, 5, 6, 7), Format.orderedWeekdays(Locale.US))
        assertEquals(listOf(2, 3, 4, 5, 6, 7, 1), Format.orderedWeekdays(Locale.UK))
    }

    @Test fun paceAndMultiplier() {
        assertEquals("1.5×", Format.multiplier(1.5))
        assertEquals("2×", Format.multiplier(2.0))
        assertEquals("1.3×", Format.multiplier(1.26))
        assertEquals("about as long as you guess", Format.paceSentence(1.02))
        assertEquals("50% longer than you guess", Format.paceSentence(1.5))
        assertEquals("15% less than you guess", Format.paceSentence(0.85))
    }

    @Test fun runClock() {
        assertEquals("12:04", Format.clock(12 * 60 + 4.9))
        assertEquals("1:36:57", Format.clock(3600 + 36 * 60 + 57.0))
        assertEquals("+3:10", Format.clock(-190.0))
    }

    @Test fun dayNames() {
        Format.zone = zone
        val now = LocalDateTime.of(2026, 9, 21, 7, 0).atZone(zone).toInstant()
        assertEquals("Today", Format.day(LocalDate.of(2026, 9, 21), now))
        assertEquals("Tomorrow", Format.day(LocalDate.of(2026, 9, 22), now))
        assertEquals("Wednesday", Format.day(LocalDate.of(2026, 9, 23), now, Locale.US))
        assertEquals("tomorrow", Format.dayPhrase(LocalDate.of(2026, 9, 22), now))
    }
}
