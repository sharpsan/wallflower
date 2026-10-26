package app.sharpsan.wallflower

import android.os.Bundle

/**
 * The method channel protocol between a wallpaper engine and its Dart isolate.
 *
 * Keep in sync with `lib/src/protocol.dart`. Bump [VERSION] on any incompatible change.
 *
 * Flow:
 * 1. Dart calls [METHOD_READY] with its [KEY_PROTOCOL] version once `runWallpaper` starts.
 * 2. Native replies with a full snapshot (all state keys plus [KEY_PROTOCOL] and [KEY_ENGINE_ID]).
 * 3. Native then pushes partial [METHOD_UPDATE] maps (coalesced to one per frame), and
 *    [METHOD_COMMAND] and [METHOD_MESSAGE] maps as they happen. Nothing is queued before
 *    [METHOD_READY].
 * 4. Dart can call [METHOD_TILT] (start or stop tilt samples, sent as [KEY_TILT] updates),
 *    [METHOD_COLORS] (colors for `onComputeColors`) and [METHOD_SEND] (a message to the app).
 */
internal object WallpaperProtocol {
    const val VERSION = 1
    const val CHANNEL = "wallflower/wallpaper"

    // Dart -> native.
    const val METHOD_READY = "ready"
    const val METHOD_TILT = "tilt"
    const val METHOD_COLORS = "colors"
    const val METHOD_SEND = "send"

    // Native -> Dart.
    const val METHOD_UPDATE = "update"
    const val METHOD_COMMAND = "command"
    const val METHOD_MESSAGE = "message"

    // Snapshot and update keys.
    const val KEY_PROTOCOL = "protocol"
    const val KEY_ENGINE_ID = "engineId"
    const val KEY_PREVIEW = "preview"
    const val KEY_VISIBLE = "visible"
    const val KEY_OFFSET = "offset"
    const val KEY_OFFSET_STEP = "offsetStep"
    const val KEY_ZOOM = "zoom"
    const val KEY_TARGET = "target"
    const val KEY_CONFIG = "config"
    const val KEY_TILT = "tilt"

    // Tilt request keys.
    const val KEY_ENABLED = "enabled"
    const val KEY_SAMPLING_PERIOD = "samplingPeriodUs"

    // Color keys: ARGB ints, plus WallpaperColors hint flags.
    const val KEY_PRIMARY = "primary"
    const val KEY_SECONDARY = "secondary"
    const val KEY_TERTIARY = "tertiary"
    const val KEY_HINTS = "hints"

    // Message keys.
    const val KEY_NAME = "name"
    const val KEY_DATA = "data"

    // Command keys.
    const val KEY_ACTION = "action"
    const val KEY_X = "x"
    const val KEY_Y = "y"
    const val KEY_Z = "z"
    const val KEY_EXTRAS = "extras"

    /** Clamps a page offset to 0..1; non-finite values become 0. */
    fun sanitizeOffset(value: Float): Double =
        if (value.isFinite()) value.coerceIn(0f, 1f).toDouble() else 0.0

    /**
     * Normalizes a page step. Launchers report `1 / (pages - 1)`, which is `Infinity` with a
     * single page, and some report 0 or -1 when they don't page at all. All of those become 0.
     */
    fun sanitizeStep(value: Float): Double =
        if (value.isFinite() && value > 0f) value.coerceAtMost(1f).toDouble() else 0.0

    /** Clamps a zoom level to 0..1; non-finite values become 0. */
    fun sanitizeZoom(value: Float): Double =
        if (value.isFinite()) value.coerceIn(0f, 1f).toDouble() else 0.0

    /** Builds a [METHOD_COMMAND] payload. Only codec-safe extras are kept. */
    fun command(action: String, x: Int, y: Int, z: Int, extras: Bundle?): Map<String, Any?> =
        mapOf(
            KEY_ACTION to action,
            KEY_X to x,
            KEY_Y to y,
            KEY_Z to z,
            KEY_EXTRAS to extras?.let(::codecSafe).orEmpty(),
        )

    private fun codecSafe(bundle: Bundle): Map<String, Any?> {
        val result = HashMap<String, Any?>()
        for (key in bundle.keySet()) {
            @Suppress("DEPRECATION")
            when (val value = bundle.get(key)) {
                null, is Boolean, is Int, is Long, is Double, is String -> result[key] = value
                is Float -> result[key] = value.toDouble()
                is Short -> result[key] = value.toInt()
                is Byte -> result[key] = value.toInt()
                else -> {}
            }
        }
        return result
    }
}
