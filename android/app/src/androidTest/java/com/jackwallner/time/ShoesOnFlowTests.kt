package com.jackwallner.time

import android.Manifest
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.compose.ui.test.ExperimentalTestApi
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertIsEnabled
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.createEmptyComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.test.performTextInput
import androidx.compose.ui.test.performTouchInput
import androidx.compose.ui.test.longClick
import androidx.test.core.app.ActivityScenario
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.jackwallner.time.data.AlertActionReceiver
import com.jackwallner.time.data.AlertScheduler
import com.jackwallner.time.data.SharedPreferencesStore
import com.jackwallner.time.model.PaceAnswer
import com.jackwallner.time.model.PlannedAlert
import com.jackwallner.time.model.day
import java.time.ZoneId
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * The first run, the free and paid boundaries, a whole morning on the run
 * screen, one-off days, and the alerts with their notification buttons, on a
 * real device. Debug launch extras seed state the way the iOS UI tests do.
 */
@OptIn(ExperimentalTestApi::class)
@RunWith(AndroidJUnit4::class)
class ShoesOnFlowTests {
    @get:Rule val compose = createEmptyComposeRule()

    private val context: Context = ApplicationProvider.getApplicationContext()
    private val graph get() = AppGraph.get(context)
    private var scenario: ActivityScenario<MainActivity>? = null

    @Before fun setUp() {
        if (Build.VERSION.SDK_INT >= 33) {
            InstrumentationRegistry.getInstrumentation().uiAutomation.grantRuntimePermission(context.packageName, Manifest.permission.POST_NOTIFICATIONS)
        }
        AppClock.offsetMillis = 0
        // This emulator draws a frame in about a second, so a one-second
        // clock tick would keep Compose busy forever.
        AppClock.runTickMillis = 30_000
        // The run screen's drifting glow is an infinite animation; like
        // "Remove animations", scale 0 holds it still so Compose can idle.
        InstrumentationRegistry.getInstrumentation().uiAutomation.executeShellCommand("settings put global animator_duration_scale 0").close()
    }

    @After fun tearDown() {
        scenario?.close()
        graph.purchases.setLocalOverride(false)
    }

    private fun launch(configure: Intent.() -> Unit) {
        val intent = Intent(context, MainActivity::class.java).apply(configure)
        scenario = ActivityScenario.launch(intent)
    }

    private fun waitForTag(tag: String, timeout: Long = 30_000) = compose.waitUntilAtLeastOneExists(hasTestTag(tag), timeout)
    private fun waitForText(text: String, timeout: Long = 30_000) = compose.waitUntilAtLeastOneExists(hasText(text, substring = true), timeout)

    private fun tapPrimary() {
        compose.onNodeWithTag("onboardingPrimary").assertIsEnabled().performClick()
        compose.waitForIdle()
    }

    @Test fun firstRunWalksSetupToTheRealPlan() {
        launch { putExtra("reset", true) }
        waitForText("Leave on time.")
        tapPrimary()
        waitForTag("pace.halfOver")
        compose.onNodeWithTag("pace.halfOver").performClick()
        tapPrimary()
        waitForText("When do you need to walk out the door?")
        tapPrimary()
        waitForText("What happens before you leave?")
        tapPrimary()
        // Guesses: 10 + 15 + 10 + 15 + 10 + 5 = 65 min at 1.5x.
        waitForTag("revealTotal")
        tapPrimary()
        // The offer: the fixture plans carry the iOS trial and prices.
        waitForText("Try Shoes On Pro free for 7 days", 45_000)
        compose.onNodeWithText("Start 7-day free trial").assertIsDisplayed()
        compose.onNodeWithTag("trialDisclosure").assertIsDisplayed()
        waitForText("then \$9.99 per year")
        compose.onNodeWithTag("getStarted").performClick()
        waitForTag("nextDeparture")
        compose.onNodeWithTag("startRun").assertIsDisplayed()
        assertTrue(graph.settings.hasCompletedSetup)
        assertEquals(1, graph.store.routines.size)
        assertEquals(PaceAnswer.HALF_OVER, graph.store.state.pace)
        assertEquals(setOf(2, 3, 4, 5, 6), graph.store.routines[0].weekdays)
        assertEquals(6, graph.store.routines[0].steps.size)
        assertFalse("Get Started never unlocks Pro", graph.purchases.isPro)
    }

    @Test fun aFreeUserMeetsThePaywallForASecondRoutine() {
        launch {
            putExtra("seed", true)
            putExtra("free", true)
        }
        waitForTag("routineMenu")
        compose.onNodeWithTag("routineMenu").performClick()
        waitForText("New routine (Pro)")
        compose.onNodeWithTag("newRoutine").performClick()
        waitForTag("paywall")
        waitForText("\$9.99 per year")
        compose.onNodeWithText("\$1.99 per month").assertIsDisplayed()
        compose.onNodeWithText("Save 58%").assertIsDisplayed()
        // Debug with no store key never sells or unlocks anything.
        compose.onNodeWithTag("subscribe").performClick()
        waitForTag("paywallError")
        assertFalse(graph.purchases.isPro)
        assertEquals(1, graph.store.routines.size)
    }

    @Test fun proOpensTheEditorAndSavesASecondRoutine() {
        launch {
            putExtra("seed", true)
            putExtra("demoPro", true)
        }
        waitForTag("routineMenu")
        assertTrue(graph.purchases.isPro)
        compose.onNodeWithTag("routineMenu").performClick()
        waitForText("New routine")
        compose.onNodeWithTag("newRoutine").performClick()
        waitForTag("editor")
        compose.onNodeWithTag("routineName").performTextInput("Gym")
        compose.onNodeWithTag("saveRoutine").performClick()
        waitForTag("nextDeparture")
        compose.waitUntil(10_000) { graph.store.routines.size == 2 }
        assertEquals("Gym", graph.store.selectedRoutine?.name)
        assertEquals(setOf(1, 7), graph.store.selectedRoutine?.weekdays)
    }

    @Test fun aWholeMorningOnTheRunScreen() {
        launch {
            putExtra("seed", true)
            putExtra("fixedNow", "07:40")
        }
        waitForTag("startRun")
        compose.onNodeWithTag("startRun").performClick()
        waitForTag("runScreen")
        val steps = graph.store.activeRun!!.steps.size
        assertEquals(5, steps)
        assertFalse(graph.store.activeRun!!.isPractice)
        // Done, then Undo puts the step back.
        Thread.sleep(800)
        compose.onNodeWithTag("done").performClick()
        waitForTag("undo")
        assertEquals(1, graph.store.activeRun?.stepIndex)
        compose.onNodeWithTag("undo").performClick()
        compose.waitUntil(10_000) { graph.store.activeRun?.stepIndex == 0 }
        // Skip one, finish the rest.
        Thread.sleep(800)
        compose.onNodeWithTag("skipStep").performClick()
        compose.waitUntil(10_000) { graph.store.activeRun?.stepIndex == 1 }
        repeat(steps - 1) {
            Thread.sleep(800)
            compose.onNodeWithTag("done").performClick()
            compose.waitForIdle()
        }
        waitForTag("outTheDoor")
        compose.onNodeWithText("Shoes on.", substring = true).assertExists()
        compose.onNodeWithTag("outTheDoor").performClick()
        waitForTag("summary")
        assertTrue(graph.store.state.departures.size >= 13)
        assertTrue(graph.store.state.lastFinished!!.run.steps[0].skipped)
        compose.onNodeWithTag("summaryDone").performClick()
        compose.waitUntil(15_000) { graph.store.state.lastFinished == null }
        waitForTag("nextDeparture")
    }

    @Test fun behindTheRunOffersACatchUpThatCanBeTakenBack() {
        launch {
            putExtra("seed", true)
            putExtra("screen", "run")
        }
        waitForTag("catchUp")
        compose.onNodeWithText("3 min behind", substring = true).assertExists()
        compose.onNodeWithTag("catchUp").performClick()
        waitForText("Put Pack bag and lunch back")
        assertTrue(graph.store.activeRun!!.steps[3].skipped)
        compose.onNodeWithTag("undo").performClick()
        compose.waitUntil(10_000) { graph.store.activeRun?.steps?.get(3)?.skipped == false }
    }

    @Test fun skippingADayFromHomeAndUndoingIt() {
        launch {
            putExtra("seed", true)
            putExtra("fixedNow", "06:00")
        }
        waitForTag("changeDay")
        compose.onNodeWithTag("changeDay").performClick()
        waitForTag("skipDay")
        compose.onNodeWithTag("skipDay").performClick()
        waitForTag("changesCard")
        compose.onNodeWithText("Skipped").assertIsDisplayed()
        assertEquals(1, graph.store.selectedRoutine!!.changes.size)
        compose.onNodeWithText("Undo").performClick()
        compose.waitUntil(10_000) { graph.store.selectedRoutine!!.changes.isEmpty() }
    }

    @Test fun aWrongReviewerCodeNeverOpensPro() {
        launch {
            putExtra("seed", true)
            putExtra("free", true)
        }
        waitForTag("settings")
        compose.onNodeWithTag("settings").performClick()
        waitForTag("settingsScreen")
        compose.onNodeWithTag("versionRow").performScrollTo().performTouchInput { longClick() }
        waitForTag("reviewCode")
        compose.onNodeWithTag("reviewCode").performTextInput("not-the-code")
        compose.onNodeWithTag("reviewCodeSubmit").performClick()
        waitForText("That code didn't work.")
        assertFalse(graph.purchases.isPro)
    }

    @Test fun alertsAreScheduledAndTheirButtonsAct() {
        launch {
            putExtra("seed", true)
            putExtra("fixedNow", "05:00")
        }
        waitForTag("nextDeparture")
        // The rolling window is on AlarmManager, ids remembered for the next rebuild.
        val scheduled = SharedPreferencesStore(context).getStringSet("alerts.scheduledIds")
        assertTrue("alerts scheduled: ${scheduled.size}", scheduled.any { it.startsWith("ready.") } && scheduled.any { it.startsWith("leave.") })
        // A get-ready alert as the alarm posts it, with its two buttons.
        val routine = graph.store.selectedRoutine!!
        val next = graph.store.nextPlan(routine, AppClock.now())!!
        val alert = PlannedAlert("ready.test", PlannedAlert.Kind.GET_READY, next.alertAt, "Time to get ready", "Start now to leave.", routine.id, next.leaveAt)
        AlertScheduler.post(context, Intent().putExtra(AlertScheduler.EXTRA_ALERT_ID, alert.id).putExtra(AlertScheduler.EXTRA_KIND, alert.kind.name)
            .putExtra(AlertScheduler.EXTRA_TITLE, alert.title).putExtra(AlertScheduler.EXTRA_BODY, alert.body)
            .putExtra(AlertScheduler.EXTRA_ROUTINE, routine.id.toString()).putExtra(AlertScheduler.EXTRA_LEAVE_AT, next.leaveAt.toEpochMilli()))
        val manager = context.getSystemService(NotificationManager::class.java)
        val posted = manager.activeNotifications.firstOrNull { it.tag == "ready.test" }
        assertNotNull(posted)
        assertEquals(listOf("Start now", "Skip this time"), posted!!.notification.actions.map { it.title.toString() })
        // "Skip this time" skips that day without opening the app.
        AlertActionReceiver().onReceive(context, Intent(AlertScheduler.ACTION_SKIP_DAY).putExtra(AlertScheduler.EXTRA_ALERT_ID, "ready.test")
            .putExtra(AlertScheduler.EXTRA_ROUTINE, routine.id.toString()).putExtra(AlertScheduler.EXTRA_LEAVE_AT, next.leaveAt.toEpochMilli()))
        val day = next.leaveAt.day(ZoneId.systemDefault())
        assertTrue(graph.store.selectedRoutine!!.change(day)?.isSkip == true)
        assertNull(manager.activeNotifications.firstOrNull { it.tag == "ready.test" })
        assertFalse(graph.store.state.departures.any { it.target == next.leaveAt })
    }

    @Test fun theRunNotificationCarriesDoneAndAdvancesTheRun() {
        launch {
            putExtra("seed", true)
            putExtra("screen", "run")
        }
        waitForTag("runScreen")
        val manager = context.getSystemService(NotificationManager::class.java)
        compose.waitUntil(10_000) { manager.activeNotifications.any { it.id == AlertScheduler.RUN_NOTIFICATION_ID } }
        val ongoing = manager.activeNotifications.first { it.id == AlertScheduler.RUN_NOTIFICATION_ID }
        assertTrue(ongoing.isOngoing)
        assertEquals("Breakfast", ongoing.notification.extras.getString("android.title"))
        assertEquals(listOf("Done"), ongoing.notification.actions.map { it.title.toString() })
        AlertActionReceiver().onReceive(context, Intent(AlertScheduler.ACTION_DONE).putExtra(AlertScheduler.EXTRA_ALERT_ID, "run.done"))
        compose.waitUntil(10_000) { graph.store.activeRun?.stepIndex == 3 }
        waitForText("Pack bag and lunch")
        // Ending the run takes the notification away.
        graph.store.cancelRun()
        compose.waitUntil(10_000) { manager.activeNotifications.none { it.id == AlertScheduler.RUN_NOTIFICATION_ID } }
    }

    @Test fun settingsTogglesRebuildTheAlerts() {
        launch {
            putExtra("seed", true)
            putExtra("fixedNow", "05:00")
            putExtra("free", true)
        }
        waitForTag("settings")
        compose.onNodeWithTag("settings").performClick()
        waitForTag("settingsScreen")
        compose.onNodeWithText("Time to get ready").performClick()
        compose.waitUntil(10_000) { !graph.settings.startAlerts }
        val scheduled = SharedPreferencesStore(context).getStringSet("alerts.scheduledIds")
        assertFalse(scheduled.any { it.startsWith("ready.") || it.startsWith("nudge") })
        assertTrue(scheduled.any { it.startsWith("leave.") })
        compose.onNodeWithText("Time to get ready").performClick()
        compose.waitUntil(10_000) { graph.settings.startAlerts }
        compose.onNodeWithTag("tryPro").performScrollTo().performClick()
        waitForTag("paywall")
    }
}
