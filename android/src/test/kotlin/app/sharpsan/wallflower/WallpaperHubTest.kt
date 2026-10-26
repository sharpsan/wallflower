package app.sharpsan.wallflower

import android.content.SharedPreferences
import kotlin.test.AfterTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

internal class WallpaperHubTest {
    private val prefs = FakeSharedPreferences()
    private val registered = mutableListOf<Any>()

    @AfterTest
    fun cleanUp() {
        for (item in registered) {
            when (item) {
                is WallpaperHub.RunningWallpaper -> WallpaperHub.unregister(item)
                is WallpaperHub.AppEndpoint -> WallpaperHub.unregister(item)
            }
        }
    }

    private fun engine(serviceClass: String, ready: Boolean = true) =
        FakeWallpaper(serviceClass, ready).also {
            WallpaperHub.register(it)
            registered += it
        }

    @Test
    fun configIsStoredPerServiceAndPushedToItsEngines() {
        val aurora = engine("com.example.Aurora")
        val clock = engine("com.example.Clock")

        WallpaperHub.setConfigJson(prefs, listOf("com.example.Aurora"), """{"speed":2}""")

        assertEquals("""{"speed":2}""", WallpaperHub.configJson(prefs, "com.example.Aurora"))
        assertNull(WallpaperHub.configJson(prefs, "com.example.Clock"))
        assertEquals(listOf<String?>("""{"speed":2}"""), aurora.configs)
        assertEquals(emptyList(), clock.configs)
    }

    @Test
    fun oneConfigCanGoToSeveralServices() {
        val aurora = engine("com.example.Aurora")
        val clock = engine("com.example.Clock")

        WallpaperHub.setConfigJson(prefs, listOf("com.example.Aurora", "com.example.Clock"), "{}")

        assertEquals("{}", WallpaperHub.configJson(prefs, "com.example.Aurora"))
        assertEquals("{}", WallpaperHub.configJson(prefs, "com.example.Clock"))
        assertEquals(listOf<String?>("{}"), aurora.configs)
        assertEquals(listOf<String?>("{}"), clock.configs)
    }

    @Test
    fun clearingTheConfigRemovesItAndPushesNull() {
        val aurora = engine("com.example.Aurora")
        WallpaperHub.setConfigJson(prefs, listOf("com.example.Aurora"), """{"a":1}""")

        WallpaperHub.setConfigJson(prefs, listOf("com.example.Aurora"), null)

        assertNull(WallpaperHub.configJson(prefs, "com.example.Aurora"))
        assertEquals(listOf("""{"a":1}""", null), aurora.configs)
    }

    @Test
    fun messagesCountOnlyEnginesThatTookThem() {
        engine("com.example.Aurora")
        engine("com.example.Aurora", ready = false)
        engine("com.example.Clock")

        assertEquals(1, WallpaperHub.sendToWallpapers(listOf("com.example.Aurora"), "ping", null))
        assertEquals(2, WallpaperHub.sendToWallpapers(listOf("com.example.Aurora", "com.example.Clock"), "ping", 1))
    }

    @Test
    fun messagesFromWallpapersReachEveryAppEndpoint() {
        val received = mutableListOf<Pair<String, Any?>>()
        val endpoints =
            listOf(
                WallpaperHub.AppEndpoint { name, data -> received.add(name to data) },
                WallpaperHub.AppEndpoint { _, _ -> false },
            )
        endpoints.forEach {
            WallpaperHub.register(it)
            registered += it
        }

        assertEquals(1, WallpaperHub.sendToApps("pong", mapOf("preview" to false)))
        assertEquals(listOf<Pair<String, Any?>>("pong" to mapOf("preview" to false)), received)
    }

    @Test
    fun unregisteredEnginesGetNothing() {
        val aurora = engine("com.example.Aurora")
        WallpaperHub.unregister(aurora)

        WallpaperHub.setConfigJson(prefs, listOf("com.example.Aurora"), "{}")

        assertEquals(0, WallpaperHub.sendToWallpapers(listOf("com.example.Aurora"), "ping", null))
        assertEquals(emptyList(), aurora.configs)
    }

    private class FakeWallpaper(override val serviceClassName: String, private val ready: Boolean) :
        WallpaperHub.RunningWallpaper {
        val configs = mutableListOf<String?>()

        override fun onConfigChanged(json: String?) {
            configs += json
        }

        override fun deliverMessage(name: String, data: Any?): Boolean = ready
    }
}

/** An in-memory SharedPreferences, enough for the config store. */
private class FakeSharedPreferences : SharedPreferences {
    private val values = mutableMapOf<String, Any?>()

    override fun getAll(): Map<String, *> = values.toMap()

    override fun getString(key: String, defValue: String?): String? = values[key] as String? ?: defValue

    override fun getStringSet(key: String, defValues: Set<String>?): Set<String>? = defValues

    override fun getInt(key: String, defValue: Int): Int = values[key] as Int? ?: defValue

    override fun getLong(key: String, defValue: Long): Long = values[key] as Long? ?: defValue

    override fun getFloat(key: String, defValue: Float): Float = values[key] as Float? ?: defValue

    override fun getBoolean(key: String, defValue: Boolean): Boolean = values[key] as Boolean? ?: defValue

    override fun contains(key: String): Boolean = key in values

    override fun edit(): SharedPreferences.Editor = Editor()

    override fun registerOnSharedPreferenceChangeListener(
        listener: SharedPreferences.OnSharedPreferenceChangeListener,
    ) {}

    override fun unregisterOnSharedPreferenceChangeListener(
        listener: SharedPreferences.OnSharedPreferenceChangeListener,
    ) {}

    private inner class Editor : SharedPreferences.Editor {
        private val changes = mutableMapOf<String, Any?>()
        private val removals = mutableSetOf<String>()
        private var clear = false

        override fun putString(key: String, value: String?): SharedPreferences.Editor = also { changes[key] = value }

        override fun putStringSet(key: String, values: Set<String>?): SharedPreferences.Editor = also { changes[key] = values }

        override fun putInt(key: String, value: Int): SharedPreferences.Editor = also { changes[key] = value }

        override fun putLong(key: String, value: Long): SharedPreferences.Editor = also { changes[key] = value }

        override fun putFloat(key: String, value: Float): SharedPreferences.Editor = also { changes[key] = value }

        override fun putBoolean(key: String, value: Boolean): SharedPreferences.Editor = also { changes[key] = value }

        override fun remove(key: String): SharedPreferences.Editor = also { removals += key }

        override fun clear(): SharedPreferences.Editor = also { clear = true }

        override fun commit(): Boolean {
            if (clear) values.clear()
            removals.forEach { values.remove(it) }
            values.putAll(changes)
            return true
        }

        override fun apply() {
            commit()
        }
    }
}
