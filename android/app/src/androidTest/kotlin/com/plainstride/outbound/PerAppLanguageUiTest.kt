package com.plainstride.outbound

import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.net.Uri
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.uiautomator.By
import androidx.test.uiautomator.Direction
import androidx.test.uiautomator.StaleObjectException
import androidx.test.uiautomator.UiDevice
import androidx.test.uiautomator.UiObject2
import androidx.test.uiautomator.Until
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.FixMethodOrder
import org.junit.Test
import org.junit.runner.RunWith
import org.junit.runners.MethodSorters
import java.io.File
import java.io.FileOutputStream

/**
 * System per-app language coverage for the installable debug app
 * (`com.plainstride.outbound.debug`).
 *
 * The tests drive the real Android Settings "App language" screen for the app,
 * switch language there, then relaunch the app and assert the app-authored copy
 * in that language while the device language stays untouched. Nothing here
 * writes app data, starts an activity recording, or resets the app.
 *
 * Requirements:
 * - Android 13+ device or emulator whose Settings UI is in English.
 * - The debug APK built from the same source is installed.
 * - The debug app is signed out so the localized sign-in surface is visible.
 *
 * Run with `scripts/run-android-per-app-language-ui-tests.sh`, which also
 * restores "System default" if the run fails partway through.
 */
@RunWith(AndroidJUnit4::class)
@FixMethodOrder(MethodSorters.NAME_ASCENDING)
class PerAppLanguageUiTest {
    private val instrumented = InstrumentationRegistry.getInstrumentation()
    private val device = UiDevice.getInstance(instrumented)
    /** Instrumentation runs as the target app, so its data directory is the writable one. */
    private val context: Context = instrumented.targetContext

    /** The debug app under test: the instrumented navigation-test package minus its suffix. */
    private val appPackage = BuildConfig.APPLICATION_ID.removeSuffix(".navigationtest") + ".debug"
    /** Internal files directory; the runner pulls it with `adb exec-out run-as ... tar`. */
    private val outputDir = File(context.filesDir, "per-app-language-ui").apply { mkdirs() }
    private val resultsFile = File(outputDir, "results.txt")
    private val screenshotList = File(outputDir, "screenshots.txt")

    /** The system-owned language of the device, recorded so a switch cannot silently move it. */
    private lateinit var deviceLocaleBefore: String

    @Before fun prepare() {
        check("setup", "Artifact directory is writable: ${outputDir.absolutePath}", outputDir.isDirectory)
        if (!resultsFile.exists()) resultsFile.writeText("")
        record("app=$appPackage sdk=${device.executeShellCommand("getprop ro.build.version.sdk").trim()}")
        assertTrue(
            "$appPackage is not installed; build and install the debug APK first",
            device.executeShellCommand("pm path $appPackage").trim().startsWith("package:"),
        )
    }

    @Test fun t01SettingsShowsAppAndSupportedLanguages() {
        deviceLocaleBefore = deviceLocaleSnapshot()
        openAppLanguagePage()

        check(
            "01-visibility",
            "Settings App language screen headers the Plainstride app",
            device.hasObject(By.textContains("Plainstride")),
            "header text missing; picker shown=${device.hasObject(By.text("All languages"))}",
        )
        check(
            "01-visibility",
            "System default choice is offered",
            findAppLanguageRow("System default") != null,
        )
        for (language in listOf(ENGLISH, SPANISH, CHINESE)) {
            check(
                "01-visibility",
                "Supported language $language is offered",
                findAppLanguageRow(language) != null,
            )
        }
        // Reopen so the picker is back at its initial scroll position after the lookups.
        openAppLanguagePage()
        check(
            "01-visibility",
            "Picker offers only the declared en/es/zh-Hans languages",
            listOf("Français", "Deutsch", "日本語").none { device.hasObject(By.text(it)) },
            "offered unexpected languages",
        )
        record("01-visibility app-locales=${localeUsage()}")
        capture("01-settings-app-language-picker")
        assertDeviceLocaleUnchanged("01-visibility")
    }

    @Test fun t02SpanishAppliesThroughSettingsUi() {
        deviceLocaleBefore = deviceLocaleSnapshot()
        selectLanguage(LANGUAGE_SPANISH_ROW, "Spani", "es", "02-spanish")
        check(
            "02-spanish",
            "System reports the app locale as Spanish",
            appLocaleTags().startsWith("es"),
            "locales=${localeUsage()}",
        )
        captureAfterReopeningPicker("02-settings-spanish-selected", "Español")
        assertAppCopy("02-spanish", "es")
        assertDeviceLocaleUnchanged("02-spanish")
    }

    @Test fun t03SpanishPersistsAcrossRelaunch() {
        deviceLocaleBefore = deviceLocaleSnapshot()
        check(
            "03-spanish-persistence",
            "Spanish app locale survived the previous scenario",
            appLocaleTags().startsWith("es"),
            "locales=${localeUsage()}",
        )
        assertAppCopy("03-spanish-persistence", "es", relaunch = true)
        assertDeviceLocaleUnchanged("03-spanish-persistence")
    }

    @Test fun t04SimplifiedChineseAppliesThroughSettingsUi() {
        deviceLocaleBefore = deviceLocaleSnapshot()
        selectLanguage(LANGUAGE_CHINESE_ROW, "Chine", "zh-Hans", "04-simplified-chinese")
        check(
            "04-simplified-chinese",
            "System reports the app locale as Simplified Chinese",
            appLocaleTags().startsWith("zh-Hans"),
            "locales=${localeUsage()}",
        )
        captureAfterReopeningPicker("04-settings-simplified-chinese-selected", "简体中文")
        assertAppCopy("04-simplified-chinese", "zh")
        assertDeviceLocaleUnchanged("04-simplified-chinese")
    }

    @Test fun t05SimplifiedChinesePersistsAcrossRelaunch() {
        deviceLocaleBefore = deviceLocaleSnapshot()
        check(
            "05-simplified-chinese-persistence",
            "Simplified Chinese app locale survived the previous scenario",
            appLocaleTags().startsWith("zh-Hans"),
            "locales=${localeUsage()}",
        )
        assertAppCopy("05-simplified-chinese-persistence", "zh", relaunch = true)
        assertDeviceLocaleUnchanged("05-simplified-chinese-persistence")
    }

    @Test fun t06ExplicitEnglishSelection() {
        deviceLocaleBefore = deviceLocaleSnapshot()
        selectLanguage(LANGUAGE_ENGLISH_ROW, "Engl", "en", "06-explicit-english")
        check(
            "06-explicit-english",
            "System reports an explicit English app locale",
            appLocaleTags().startsWith("en"),
            "locales=${localeUsage()}",
        )
        assertAppCopy("06-explicit-english", "en")
        assertDeviceLocaleUnchanged("06-explicit-english")
    }

    @Test fun t99SystemDefaultRestoresDeviceLanguage() {
        deviceLocaleBefore = deviceLocaleSnapshot()
        openAppLanguagePage()
        check("99-system-default", "System default row is available", findAppLanguageRow("System default") != null)
        check("99-system-default", "Tapped the System default row", clickRow("System default", "99-system-default"))
        check(
            "99-system-default",
            "App locale returns to System default",
            waitForLocale("", 10_000),
            "locales=${localeUsage()}",
        )
        captureAfterReopeningPicker("99-settings-system-default-selected", "System default")
        assertAppCopy("99-system-default", "en", relaunch = true)
        assertDeviceLocaleUnchanged("99-system-default")
        record("99-system-default final-locales=${localeUsage()} device=${deviceLocaleSnapshot()}")
    }

    // Settings-driving helpers -------------------------------------------------

    private fun openAppLanguagePage() {
        // A fresh Settings process keeps the picker state independent of earlier scenarios.
        device.executeShellCommand("am force-stop com.android.settings")
        val intent = Intent(ACTION_APP_LOCALE_SETTINGS).apply {
            data = Uri.parse("package:$appPackage")
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        context.startActivity(intent)
        check(
            "settings",
            "App language screen opened for $appPackage",
            device.wait(Until.hasObject(By.text("All languages")), 15_000),
        )
        device.waitForIdle()
    }

    /**
     * Finds a picker row, scrolling the language list when the row sits below the
     * fold. Rows that the gesture bar partly covers cannot be tapped reliably, so
     * only fully visible rows are returned.
     */
    private fun findAppLanguageRow(label: String): UiObject2? {
        fun fullyVisible(row: UiObject2?): UiObject2? = row?.takeIf {
            val bounds = it.visibleBounds
            bounds.height() > 0 && bounds.top >= 0 && bounds.bottom <= device.displayHeight - 64
        }

        fullyVisible(device.wait(Until.findObject(By.text(label)), 5_000))?.let { return it }
        val list = device.findObjects(By.scrollable(true)).firstOrNull() ?: return null
        repeat(12) {
            list.scroll(Direction.DOWN, 0.35f)
            device.waitForIdle()
            fullyVisible(device.findObject(By.text(label)))?.let { return it }
        }
        return null
    }

    /**
     * Picks a language the way a person would: through the picker's search field,
     * which lists the language at the top regardless of how long the list is.
     */
    private fun selectLanguage(rowLabel: String, query: String, expectedTagPrefix: String, scenario: String) {
        openAppLanguagePage()
        // A Suggested regional variant applies in one tap; only languages the system
        // does not suggest (Simplified Chinese on a fresh install) need the search row.
        val variant = findSuggestedVariantRow(rowLabel)
        if (variant != null) {
            val variantLabel = variant.text
            record("$scenario suggested-row=$variantLabel")
            check(scenario, "Tapped the $variantLabel suggested row", clickRow(variantLabel, scenario))
        } else {
            check(scenario, "$rowLabel search row is available", searchForLanguageRow(query, rowLabel))
            check(scenario, "Tapped the $rowLabel row", clickRow(rowLabel, scenario))
        }
        if (waitForLocale(expectedTagPrefix, 3_000)) return
        // Some languages ask for a regional variant before the choice is applied.
        val regionChooserShown = waitForRegionChooser(6_000)
        record("$scenario region-chooser=$regionChooserShown texts=${visibleTexts()}")
        if (regionChooserShown) {
            check("$scenario-region", "$rowLabel asked for a region", true)
            clickFirstSuggestedRegion()
        }
        check(
            scenario,
            "Settings applied the $rowLabel app locale",
            waitForLocale(expectedTagPrefix, 15_000),
            "locales=${localeUsage()}",
        )
    }

    /** A Suggested row such as "Español (Estados Unidos)" for the requested language. */
    private fun findSuggestedVariantRow(label: String): UiObject2? =
        device.findObjects(By.textStartsWith(label)).firstOrNull { it.text != label }

    private fun searchForLanguageRow(query: String, rowLabel: String): Boolean {
        val search = device.findObject(By.desc("Search")) ?: return false
        search.click()
        val field = device.wait(Until.findObject(By.clazz("android.widget.AutoCompleteTextView")), 5_000) ?: return false
        field.setText(query)
        device.waitForIdle()
        // Queries are prefixes of the language name, so the typed text never matches the row.
        val found = device.wait(Until.hasObject(By.text(rowLabel)), 6_000)
        Thread.sleep(500) // The filtered list re-renders and briefly invalidates result nodes.
        return found
    }

    /**
     * Taps a row by label with a real touch at its centre. Settings rows are often
     * non-clickable title views inside a clickable row, so an accessibility click
     * on the text node is a no-op; a coordinate tap reaches the row itself.
     */
    private fun clickRow(label: String, scenario: String): Boolean {
        repeat(5) {
            val row = device.findObject(By.text(label))
            if (row == null) {
                Thread.sleep(300)
                return@repeat
            }
            val bounds = try {
                row.visibleBounds
            } catch (stale: StaleObjectException) {
                record("$scenario retried a stale $label row")
                Thread.sleep(300)
                return@repeat
            }
            device.click(bounds.centerX(), bounds.centerY())
            return true
        }
        return false
    }

    private fun waitForRegionChooser(timeoutMs: Long): Boolean {
        val deadline = System.currentTimeMillis() + timeoutMs
        while (System.currentTimeMillis() < deadline) {
            if (device.hasObject(By.text("All regions")) || device.hasObject(By.textContains("The region you choose"))) return true
            Thread.sleep(200)
        }
        return false
    }

    private fun clickFirstSuggestedRegion() {
        val rows = device.findObjects(By.clazz("android.widget.TextView")).sortedBy { it.visibleBounds.top }
        val suggested = rows.indexOfFirst { it.text == "Suggested" }
        check("settings", "Regional variant list is shown", suggested >= 0, "texts=${visibleTexts()}")
        val region = rows.getOrNull(suggested + 1)
        check("settings", "Regional variant row is shown", region != null, "texts=${visibleTexts()}")
        val regionLabel = region!!.text
        record("settings region=$regionLabel")
        check("settings", "Tapped the $regionLabel regional variant", clickRow(regionLabel, "settings-region"))
        device.waitForIdle()
    }

    private fun visibleTexts(): String = device.findObjects(By.clazz("android.widget.TextView"))
        .mapNotNull { it.text }
        .filter { it.isNotBlank() }
        .joinToString("|")

    private fun captureAfterReopeningPicker(name: String, expectedRow: String) {
        openAppLanguagePage()
        check(
            "settings",
            "Settings reflects the applied choice ($expectedRow)",
            device.wait(Until.hasObject(By.textContains(expectedRow)), 10_000),
        )
        capture(name)
    }

    // App-driving helpers ------------------------------------------------------

    /**
     * Launches the installed debug app and asserts the localized sign-in surface.
     * `relaunch` forces a process restart so persistence is exercised.
     */
    private fun assertAppCopy(scenario: String, languageKey: String, relaunch: Boolean = false) {
        val (callToAction, headline) = SIGN_IN_COPY.getValue(languageKey)
        if (relaunch) device.executeShellCommand("am force-stop $appPackage")
        // `monkey` uses the launcher intent, so the test needs no package-visibility queries.
        device.executeShellCommand("monkey -p $appPackage -c android.intent.category.LAUNCHER 1")
        check(
            scenario,
            "App renders $languageKey sign-in action \"$callToAction\"",
            device.wait(Until.hasObject(By.textContains(callToAction)), 30_000),
        )
        check(
            scenario,
            "App renders $languageKey headline \"$headline\"",
            device.wait(Until.hasObject(By.textContains(headline)), 15_000),
        )
        device.waitForIdle()
        capture("$scenario-app-$languageKey")
        record("$scenario app-locales=${localeUsage()} device=${deviceLocaleSnapshot()}")
    }

    // Assertions and evidence --------------------------------------------------

    private fun check(scenario: String, description: String, condition: Boolean, detail: String = "") {
        val detailSuffix = if (detail.isBlank()) "" else " ($detail)"
        if (condition) {
            record("PASS [$scenario] $description")
        } else {
            record("FAIL [$scenario] $description$detailSuffix")
        }
        assertTrue("$scenario: $description$detailSuffix", condition)
    }

    private fun assertDeviceLocaleUnchanged(scenario: String) {
        val now = deviceLocaleSnapshot()
        check(scenario, "Device language stayed independent of the app language", now == deviceLocaleBefore, "before=$deviceLocaleBefore now=$now")
    }

    private fun appLocaleTags(): String {
        val usage = localeUsage()
        return usage.substringAfter("[", "").substringBefore("]")
    }

    private fun localeUsage(): String = device.executeShellCommand("cmd locale get-app-locales $appPackage").trim()

    private fun waitForLocale(expectedPrefix: String, timeoutMs: Long): Boolean {
        val deadline = System.currentTimeMillis() + timeoutMs
        while (System.currentTimeMillis() < deadline) {
            val tags = appLocaleTags()
            val matches = if (expectedPrefix.isEmpty()) tags.isEmpty() else tags.startsWith(expectedPrefix)
            if (matches) return true
            Thread.sleep(200)
        }
        return false
    }

    private fun deviceLocaleSnapshot(): String = listOf("ro.product.locale", "persist.sys.locale")
        .joinToString(";") { property -> "$property=${device.executeShellCommand("getprop $property").trim()}" } +
        ";system_locales=" + device.executeShellCommand("settings get system system_locales").trim()

    private fun capture(name: String) {
        device.waitForIdle()
        val bitmap = instrumented.uiAutomation.takeScreenshot()
        check("screenshot", "Captured $name", bitmap != null)
        val file = File(outputDir, "$name.png")
        FileOutputStream(file).use { bitmap!!.compress(Bitmap.CompressFormat.PNG, 100, it) }
        screenshotList.appendText("$name ${file.absolutePath}\n")
        record("ARTIFACT $name ${file.absolutePath}")
    }

    private fun record(line: String) {
        resultsFile.appendText(line + "\n")
    }

    private companion object {
        const val ACTION_APP_LOCALE_SETTINGS = "android.settings.APP_LOCALE_SETTINGS"

        /** Row labels the system picker shows for the app's declared en/es/zh-Hans locales. */
        const val ENGLISH = "English"
        const val SPANISH = "Español"
        const val CHINESE = "简体中文"
        const val LANGUAGE_ENGLISH_ROW = ENGLISH
        const val LANGUAGE_SPANISH_ROW = SPANISH
        const val LANGUAGE_CHINESE_ROW = CHINESE

        /** App-authored sign-in copy per language: action, then headline. */
        val SIGN_IN_COPY = mapOf(
            "en" to ("Continue with Google" to "Train with purpose"),
            "es" to ("Continuar con Google" to "Entrena con intención"),
            "zh" to ("使用 Google 继续" to "有目标地训练"),
        )
    }
}
