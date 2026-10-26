package app.sharpsan.wallflower

import android.content.Context
import android.content.SharedPreferences

/**
 * Process-wide registry of running wallpaper engines and app-side endpoints, across all
 * [FlutterWallpaperService] subclasses in the process. Owns the persisted wallpaper config and
 * routes messages between the app and its wallpapers. Main thread only.
 */
internal object WallpaperHub {
    private const val PREFS = "app.sharpsan.wallflower"
    private const val CONFIG_KEY_PREFIX = "config/"

    private var lastEngineId = 0
    private val engines = LinkedHashSet<RunningWallpaper>()
    private val appEndpoints = LinkedHashSet<AppEndpoint>()

    /** A running wallpaper engine, as far as the hub is concerned. */
    interface RunningWallpaper {
        /** The service class the engine belongs to; config and messages are keyed by it. */
        val serviceClassName: String

        /** Pushes a new config: a JSON object string, or null when it was cleared. */
        fun onConfigChanged(json: String?)

        /** Delivers a message from the app. Returns true if it was delivered. */
        fun deliverMessage(name: String, data: Any?): Boolean
    }

    /** Receives messages that wallpapers send to the app. */
    fun interface AppEndpoint {
        /** Returns true if the message was delivered. */
        fun onWallpaperMessage(name: String, data: Any?): Boolean
    }

    /**
     * True while [EngineHost] spawns a wallpaper engine. Plugins are attached during the spawn, so
     * [LiveWallpaperPlugin] uses this to tell wallpaper engines from the app's own engines.
     */
    var spawningWallpaperEngine = false
        private set

    fun <T> spawningWallpaperEngine(block: () -> T): T {
        spawningWallpaperEngine = true
        try {
            return block()
        } finally {
            spawningWallpaperEngine = false
        }
    }

    /** Ids are unique per process and never reused. */
    fun nextEngineId(): Int = ++lastEngineId

    fun register(engine: RunningWallpaper) {
        engines.add(engine)
    }

    fun unregister(engine: RunningWallpaper) {
        engines.remove(engine)
    }

    fun register(endpoint: AppEndpoint) {
        appEndpoints.add(endpoint)
    }

    fun unregister(endpoint: AppEndpoint) {
        appEndpoints.remove(endpoint)
    }

    /** Snapshot of the running engines, safe to iterate while engines come and go. */
    val runningEngines: List<RunningWallpaper>
        get() = engines.toList()

    /** The persisted config of [serviceClass], as a JSON object string, or null if never set. */
    fun configJson(context: Context, serviceClass: String): String? = configJson(prefs(context), serviceClass)

    fun configJson(prefs: SharedPreferences, serviceClass: String): String? =
        prefs.getString(CONFIG_KEY_PREFIX + serviceClass, null)

    /**
     * Persists [json] (null clears it) for each of [serviceClasses] and pushes it to their running
     * engines.
     */
    fun setConfigJson(context: Context, serviceClasses: Collection<String>, json: String?) =
        setConfigJson(prefs(context), serviceClasses, json)

    fun setConfigJson(prefs: SharedPreferences, serviceClasses: Collection<String>, json: String?) {
        val editor = prefs.edit()
        for (serviceClass in serviceClasses) {
            if (json == null) {
                editor.remove(CONFIG_KEY_PREFIX + serviceClass)
            } else {
                editor.putString(CONFIG_KEY_PREFIX + serviceClass, json)
            }
        }
        editor.apply()
        runningEngines
            .filter { it.serviceClassName in serviceClasses }
            .forEach { it.onConfigChanged(json) }
    }

    /** Delivers a message to the running engines of [serviceClasses]. Returns how many got it. */
    fun sendToWallpapers(serviceClasses: Collection<String>, name: String, data: Any?): Int =
        runningEngines
            .filter { it.serviceClassName in serviceClasses }
            .count { it.deliverMessage(name, data) }

    /** Delivers a message from a wallpaper to the app's engines. Returns how many got it. */
    fun sendToApps(name: String, data: Any?): Int =
        appEndpoints.toList().count { it.onWallpaperMessage(name, data) }

    private fun prefs(context: Context): SharedPreferences =
        context.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
}
