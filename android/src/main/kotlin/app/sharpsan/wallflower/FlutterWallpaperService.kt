package app.sharpsan.wallflower

import android.app.WallpaperColors
import android.content.ComponentCallbacks2
import android.content.ComponentName
import android.content.Context
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.graphics.Color
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.service.wallpaper.WallpaperService
import android.text.format.DateFormat
import android.util.Log
import android.view.Choreographer
import android.view.MotionEvent
import android.view.SurfaceHolder
import android.view.WindowInsets
import android.view.WindowManager
import androidx.annotation.ColorInt
import io.flutter.embedding.android.AndroidTouchProcessor
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.renderer.FlutterUiDisplayListener
import io.flutter.embedding.engine.systemchannels.SettingsChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * A live wallpaper whose content is a Flutter widget tree.
 *
 * Each wallpaper engine (the applied wallpaper, the picker preview) gets its own Flutter engine,
 * spawned from a shared engine group, running the Dart entrypoint named by the service's
 * `wallflower.entrypoint` meta-data (default `wallpaperMain`). The entrypoint must be annotated
 * with `@pragma('vm:entry-point')` and should call `runWallpaper`.
 *
 * Declare this class in the app manifest, or an empty subclass per picker entry:
 * ```xml
 * <service
 *     android:name="app.sharpsan.wallflower.FlutterWallpaperService"
 *     android:permission="android.permission.BIND_WALLPAPER"
 *     android:exported="true">
 *   <intent-filter>
 *     <action android:name="android.service.wallpaper.WallpaperService" />
 *   </intent-filter>
 *   <meta-data android:name="android.service.wallpaper" android:resource="@xml/wallpaper" />
 *   <meta-data android:name="wallflower.entrypoint" android:value="wallpaperMain" />
 * </service>
 * ```
 *
 * If the Flutter engine can't start, the wallpaper draws [getFallbackColor] instead of crashing:
 * repeated crashes make Android reset the user's wallpaper to the default.
 */
open class FlutterWallpaperService : WallpaperService() {
    private val engines = LinkedHashSet<FlutterWallpaperEngine>()

    private val serviceMetaData: Bundle? by lazy {
        val component = ComponentName(this, javaClass)
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                packageManager.getServiceInfo(
                    component,
                    PackageManager.ComponentInfoFlags.of(PackageManager.GET_META_DATA.toLong()),
                ).metaData
            } else {
                @Suppress("DEPRECATION")
                packageManager.getServiceInfo(component, PackageManager.GET_META_DATA).metaData
            }
        } catch (e: PackageManager.NameNotFoundException) {
            null
        }
    }

    /**
     * The Dart function each wallpaper engine runs. Defaults to the `wallflower.entrypoint`
     * meta-data on this service, or `wallpaperMain`.
     */
    open fun getDartEntrypointFunctionName(): String =
        serviceMetaData?.getString(META_ENTRYPOINT)?.takeIf { it.isNotBlank() } ?: DEFAULT_ENTRYPOINT

    /**
     * The library that declares [getDartEntrypointFunctionName], such as
     * `package:my_app/wallpaper.dart`. Defaults to the `wallflower.entrypointLibrary` meta-data,
     * or null for the app's main library.
     */
    open fun getDartEntrypointLibraryUri(): String? =
        serviceMetaData?.getString(META_ENTRYPOINT_LIBRARY)?.takeIf { it.isNotBlank() }

    /** The color drawn instead of the Flutter scene if the engine fails. Black by default. */
    @ColorInt
    open fun getFallbackColor(): Int = Color.BLACK

    override fun onCreateEngine(): Engine = FlutterWallpaperEngine()

    override fun onTrimMemory(level: Int) {
        super.onTrimMemory(level)
        engines.toList().forEach { it.onTrimMemory(level) }
    }

    override fun onConfigurationChanged(newConfig: Configuration) {
        super.onConfigurationChanged(newConfig)
        engines.toList().forEach { it.onConfigurationChanged(newConfig) }
    }

    /**
     * Bridges one `WallpaperService.Engine` to one Flutter engine. All Flutter embedding calls live
     * in this class. Every callback runs on the main thread, which is also Flutter's UI thread.
     */
    internal inner class FlutterWallpaperEngine : Engine(), WallpaperHub.RunningWallpaper {
        private val service = this@FlutterWallpaperService
        private val engineId = WallpaperHub.nextEngineId()
        private val mainHandler = Handler(Looper.getMainLooper())
        private val viewport = ViewportMetricsFactory()

        private var flutterEngine: FlutterEngine? = null
        private var channel: MethodChannel? = null
        private var touchProcessor: AndroidTouchProcessor? = null
        private var renderingToSurface = false
        private var failed = false
        private var destroyed = false
        private var dartReady = false
        private var firstFrameRendered = false

        // State mirrored to Dart.
        private var visible = false
        private var offsetX = 0.0
        private var offsetY = 0.0
        private var stepX = 0.0
        private var stepY = 0.0
        private var zoom = 0.0
        private var target: Int? = null

        // Tilt: on only while Dart has listeners and the wallpaper is visible.
        private var tiltRequested = false
        private var tiltSamplingMicros = TILT_SAMPLING_DEFAULT_MICROS
        private val tiltSensorLazy = lazy {
            TiltSensor(service, ::displayRotation) { x, y, rotation ->
                coalescer.put(WallpaperProtocol.KEY_TILT, listOf(x, y, rotation))
            }
        }
        private val tiltSensor by tiltSensorLazy

        // The last colors Dart reported (a WallpaperColors on API 27+), for onComputeColors.
        private var colors: Any? = null

        /** The service class this engine belongs to; config and messages are keyed by it. */
        override val serviceClassName: String
            get() = service.javaClass.name

        private val coalescer =
            UpdateCoalescer(ChoreographerScheduler()) { send(WallpaperProtocol.METHOD_UPDATE, it) }
        private val visibility =
            VisibilitySettler(HandlerScheduler(mainHandler), HIDE_SETTLE_MILLIS, ::applyVisibility)

        private val displayListener =
            object : FlutterUiDisplayListener {
                override fun onFlutterUiDisplayed() {
                    firstFrameRendered = true
                    mainHandler.removeCallbacks(firstFrameWarning)
                }

                override fun onFlutterUiNoLongerDisplayed() {}
            }

        private val firstFrameWarning = Runnable {
            if (!firstFrameRendered && !failed && !destroyed) {
                Log.w(
                    TAG,
                    "Wallpaper engine $engineId: no Flutter frame ${FIRST_FRAME_WARNING_MILLIS}ms " +
                        "after becoming visible. Check that the Dart function " +
                        "'${getDartEntrypointFunctionName()}' exists, is annotated with " +
                        "@pragma('vm:entry-point'), and calls runWallpaper().",
                )
            }
        }

        override fun onCreate(surfaceHolder: SurfaceHolder) {
            super.onCreate(surfaceHolder)
            engines.add(this)
            WallpaperHub.register(this)
            setTouchEventsEnabled(true)
            setOffsetNotificationsEnabled(true)
            // No flags callback arrives when the wallpaper is first applied, so read them now.
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                target = wallpaperFlags
            }
            guarded("start the Flutter engine") { startFlutter() }
            Log.d(
                TAG,
                "Wallpaper engine $engineId created (preview=$isPreview, " +
                    "entrypoint=${getDartEntrypointFunctionName()}, failed=$failed)",
            )
        }

        private fun startFlutter() {
            val engine =
                EngineHost.spawn(
                    service,
                    getDartEntrypointFunctionName(),
                    getDartEntrypointLibraryUri(),
                )
            flutterEngine = engine
            touchProcessor = AndroidTouchProcessor(engine.renderer, false)
            engine.renderer.addIsDisplayingFlutterUiListener(displayListener)
            channel =
                MethodChannel(engine.dartExecutor.binaryMessenger, WallpaperProtocol.CHANNEL).also {
                    it.setMethodCallHandler(::onMethodCall)
                }
            viewport.setDisplay(displayContextCompat())
            sendSettings(engine, service.resources.configuration)
        }

        override fun onSurfaceCreated(holder: SurfaceHolder) {
            super.onSurfaceCreated(holder)
            guarded("attach the wallpaper surface") {
                val engine = flutterEngine ?: return@guarded
                engine.renderer.startRenderingToSurface(holder.surface, false)
                renderingToSurface = true
            }
        }

        override fun onSurfaceChanged(holder: SurfaceHolder, format: Int, width: Int, height: Int) {
            super.onSurfaceChanged(holder, format, width, height)
            viewport.setSize(width, height)
            if (failed) {
                drawFallback(holder)
                return
            }
            guarded("resize the wallpaper surface") {
                val engine = flutterEngine ?: return@guarded
                engine.renderer.surfaceChanged(width, height)
                engine.renderer.setViewportMetrics(viewport.metrics)
            }
        }

        override fun onSurfaceRedrawNeeded(holder: SurfaceHolder) {
            super.onSurfaceRedrawNeeded(holder)
            // Flutter draws on its own schedule. Blocking here until the first frame would
            // deadlock: the first frame needs this (merged platform/UI) thread.
            if (failed) drawFallback(holder)
        }

        override fun onSurfaceDestroyed(holder: SurfaceHolder) {
            detachSurface()
            super.onSurfaceDestroyed(holder)
        }

        override fun onApplyWindowInsets(insets: WindowInsets) {
            super.onApplyWindowInsets(insets)
            viewport.setInsets(insets)
            sendMetrics()
        }

        override fun onVisibilityChanged(visible: Boolean) {
            super.onVisibilityChanged(visible)
            visibility.onVisibilityChanged(visible)
        }

        override fun onOffsetsChanged(
            xOffset: Float,
            yOffset: Float,
            xOffsetStep: Float,
            yOffsetStep: Float,
            xPixelOffset: Int,
            yPixelOffset: Int,
        ) {
            val x = WallpaperProtocol.sanitizeOffset(xOffset)
            val y = WallpaperProtocol.sanitizeOffset(yOffset)
            if (x != offsetX || y != offsetY) {
                offsetX = x
                offsetY = y
                coalescer.put(WallpaperProtocol.KEY_OFFSET, listOf(x, y))
            }
            val sx = WallpaperProtocol.sanitizeStep(xOffsetStep)
            val sy = WallpaperProtocol.sanitizeStep(yOffsetStep)
            if (sx != stepX || sy != stepY) {
                stepX = sx
                stepY = sy
                coalescer.put(WallpaperProtocol.KEY_OFFSET_STEP, listOf(sx, sy))
            }
        }

        override fun onZoomChanged(zoom: Float) {
            val value = WallpaperProtocol.sanitizeZoom(zoom)
            if (value != this.zoom) {
                this.zoom = value
                coalescer.put(WallpaperProtocol.KEY_ZOOM, value)
            }
        }

        override fun onWallpaperFlagsChanged(which: Int) {
            if (which != target) {
                target = which
                coalescer.put(WallpaperProtocol.KEY_TARGET, which)
            }
        }

        override fun onComputeColors(): WallpaperColors? = colors as WallpaperColors?

        override fun onTouchEvent(event: MotionEvent) {
            super.onTouchEvent(event)
            if (failed) return
            logged("forward a touch event") { touchProcessor?.onTouchEvent(event) }
        }

        override fun onCommand(
            action: String,
            x: Int,
            y: Int,
            z: Int,
            extras: Bundle?,
            resultRequested: Boolean,
        ): Bundle? {
            if (dartReady) {
                // Deliver pending state first, so Dart sees current offsets with the command.
                coalescer.flush()
                send(WallpaperProtocol.METHOD_COMMAND, WallpaperProtocol.command(action, x, y, z, extras))
            }
            return super.onCommand(action, x, y, z, extras, resultRequested)
        }

        override fun onDestroy() {
            Log.d(TAG, "Wallpaper engine $engineId destroyed")
            destroyed = true
            visibility.cancel()
            updateTilt()
            teardownFlutter()
            engines.remove(this)
            WallpaperHub.unregister(this)
            super.onDestroy()
        }

        /** Pushes a new config (a JSON object string, or null) to Dart. */
        override fun onConfigChanged(json: String?) {
            coalescer.put(WallpaperProtocol.KEY_CONFIG, json)
        }

        /** Delivers an app message to Dart. Returns false if Dart isn't listening yet. */
        override fun deliverMessage(name: String, data: Any?): Boolean {
            if (!dartReady || destroyed) return false
            coalescer.flush()
            send(
                WallpaperProtocol.METHOD_MESSAGE,
                mapOf(WallpaperProtocol.KEY_NAME to name, WallpaperProtocol.KEY_DATA to data),
            )
            return true
        }

        fun onTrimMemory(level: Int) {
            val engine = flutterEngine ?: return
            logged("forward memory pressure") {
                // Same policy as FlutterActivity: don't slow down the first frame with a GC.
                @Suppress("DEPRECATION")
                if (firstFrameRendered && level >= ComponentCallbacks2.TRIM_MEMORY_RUNNING_LOW) {
                    engine.dartExecutor.notifyLowMemoryWarning()
                    engine.systemChannel.sendMemoryPressureWarning()
                }
                engine.renderer.onTrimMemory(level)
            }
        }

        fun onConfigurationChanged(config: Configuration) {
            val engine = flutterEngine ?: return
            logged("apply a configuration change") {
                viewport.setDisplay(displayContextCompat())
                sendSettings(engine, config)
                sendMetrics()
            }
        }

        private fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
            when (call.method) {
                WallpaperProtocol.METHOD_READY -> {
                    val dartVersion = call.argument<Int>(WallpaperProtocol.KEY_PROTOCOL)
                    if (dartVersion != WallpaperProtocol.VERSION) {
                        Log.w(
                            TAG,
                            "Wallpaper engine $engineId: Dart speaks protocol $dartVersion, " +
                                "native speaks ${WallpaperProtocol.VERSION}. Rebuild the app.",
                        )
                    }
                    dartReady = true
                    coalescer.clear()
                    result.success(snapshot())
                }
                WallpaperProtocol.METHOD_TILT -> {
                    tiltRequested = call.argument<Boolean>(WallpaperProtocol.KEY_ENABLED) == true
                    call.argument<Int>(WallpaperProtocol.KEY_SAMPLING_PERIOD)?.let {
                        tiltSamplingMicros = it.coerceAtLeast(0)
                    }
                    updateTilt()
                    result.success(tiltSensor.available)
                }
                WallpaperProtocol.METHOD_COLORS -> {
                    setColors(call)
                    result.success(null)
                }
                WallpaperProtocol.METHOD_SEND -> {
                    val name = call.argument<String>(WallpaperProtocol.KEY_NAME)
                    if (name == null) {
                        result.error("bad_args", "'name' is required.", null)
                    } else {
                        result.success(WallpaperHub.sendToApps(name, call.argument<Any?>(WallpaperProtocol.KEY_DATA)))
                    }
                }
                else -> result.notImplemented()
            }
        }

        private fun snapshot(): Map<String, Any?> =
            mapOf(
                WallpaperProtocol.KEY_PROTOCOL to WallpaperProtocol.VERSION,
                WallpaperProtocol.KEY_ENGINE_ID to engineId,
                WallpaperProtocol.KEY_PREVIEW to isPreview,
                WallpaperProtocol.KEY_VISIBLE to visible,
                WallpaperProtocol.KEY_OFFSET to listOf(offsetX, offsetY),
                WallpaperProtocol.KEY_OFFSET_STEP to listOf(stepX, stepY),
                WallpaperProtocol.KEY_ZOOM to zoom,
                WallpaperProtocol.KEY_TARGET to target,
                WallpaperProtocol.KEY_CONFIG to WallpaperHub.configJson(service, serviceClassName),
            )

        private fun updateTilt() {
            if (tiltRequested && visible && !failed && !destroyed) {
                tiltSensor.start(tiltSamplingMicros)
            } else if (tiltSensorLazy.isInitialized()) {
                tiltSensor.stop()
            }
        }

        private fun setColors(call: MethodCall) {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O_MR1) return
            val primary = call.argument<Number>(WallpaperProtocol.KEY_PRIMARY)?.toInt()
            colors =
                if (primary == null) {
                    null
                } else {
                    val secondary = call.argument<Number>(WallpaperProtocol.KEY_SECONDARY)?.toInt()
                    val tertiary = call.argument<Number>(WallpaperProtocol.KEY_TERTIARY)?.toInt()
                    val hints = call.argument<Int>(WallpaperProtocol.KEY_HINTS) ?: 0
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                        WallpaperColors(
                            android.graphics.Color.valueOf(primary),
                            secondary?.let { android.graphics.Color.valueOf(it) },
                            tertiary?.let { android.graphics.Color.valueOf(it) },
                            hints,
                        )
                    } else {
                        WallpaperColors(
                            android.graphics.Color.valueOf(primary),
                            secondary?.let { android.graphics.Color.valueOf(it) },
                            tertiary?.let { android.graphics.Color.valueOf(it) },
                        )
                    }
                }
            notifyColorsChanged()
        }

        @Suppress("DEPRECATION")
        private fun displayRotation(): Int {
            val defaultRotation = {
                (service.getSystemService(Context.WINDOW_SERVICE) as WindowManager).defaultDisplay.rotation
            }
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return defaultRotation()
            return try {
                displayContextCompat().display.rotation
            } catch (e: UnsupportedOperationException) {
                // Thrown by contexts that aren't associated with a display.
                defaultRotation()
            }
        }

        private fun applyVisibility(visible: Boolean) {
            this.visible = visible
            guarded("change the lifecycle state") {
                val engine = flutterEngine ?: return@guarded
                if (visible) {
                    engine.lifecycleChannel.appIsResumed()
                } else {
                    engine.lifecycleChannel.appIsPaused()
                }
            }
            if (visible && !firstFrameRendered) {
                mainHandler.postDelayed(firstFrameWarning, FIRST_FRAME_WARNING_MILLIS)
            } else if (!visible) {
                mainHandler.removeCallbacks(firstFrameWarning)
            }
            updateTilt()
            coalescer.put(WallpaperProtocol.KEY_VISIBLE, visible)
            coalescer.flush()
        }

        private fun send(method: String, arguments: Map<String, Any?>) {
            if (!dartReady || destroyed) return
            logged("send '$method' to Dart") { channel?.invokeMethod(method, arguments) }
        }

        private fun sendMetrics() {
            if (!viewport.hasSize) return
            val engine = flutterEngine ?: return
            logged("send viewport metrics") { engine.renderer.setViewportMetrics(viewport.metrics) }
        }

        private fun sendSettings(engine: FlutterEngine, config: Configuration) {
            val night =
                config.uiMode and Configuration.UI_MODE_NIGHT_MASK == Configuration.UI_MODE_NIGHT_YES
            engine.settingsChannel
                .startMessage()
                .setTextScaleFactor(config.fontScale)
                .setDisplayMetrics(displayContextCompat().resources.displayMetrics)
                .setUse24HourFormat(DateFormat.is24HourFormat(service))
                .setPlatformBrightness(
                    if (night) {
                        SettingsChannel.PlatformBrightness.dark
                    } else {
                        SettingsChannel.PlatformBrightness.light
                    }
                )
                .send()
            engine.localizationPlugin.sendLocalesToFlutter(config)
        }

        private fun displayContextCompat(): Context =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) displayContext ?: service else service

        private fun detachSurface() {
            if (!renderingToSurface) return
            renderingToSurface = false
            logged("detach the wallpaper surface") { flutterEngine?.renderer?.stopRenderingToSurface() }
        }

        /** Releases the Flutter engine. Safe to call more than once. */
        private fun teardownFlutter() {
            dartReady = false
            coalescer.clear()
            mainHandler.removeCallbacks(firstFrameWarning)
            val engine = flutterEngine ?: return
            channel?.setMethodCallHandler(null)
            channel = null
            touchProcessor = null
            logged("remove the display listener") {
                engine.renderer.removeIsDisplayingFlutterUiListener(displayListener)
            }
            detachSurface()
            flutterEngine = null
            logged("destroy the Flutter engine") { engine.destroy() }
        }

        private fun fail(what: String, error: Throwable) {
            Log.e(TAG, "Wallpaper engine $engineId: failed to $what. Drawing the fallback color.", error)
            if (failed) return
            failed = true
            updateTilt()
            teardownFlutter()
            val holder = surfaceHolder
            if (holder.surface?.isValid == true) drawFallback(holder)
        }

        private fun drawFallback(holder: SurfaceHolder) {
            logged("draw the fallback color") {
                val canvas = holder.lockCanvas() ?: return@logged
                try {
                    canvas.drawColor(getFallbackColor())
                } finally {
                    holder.unlockCanvasAndPost(canvas)
                }
            }
        }

        /** Runs [block]; any failure switches this engine to the fallback color. */
        private inline fun guarded(what: String, block: () -> Unit) {
            if (failed || destroyed) return
            try {
                block()
            } catch (e: Exception) {
                fail(what, e)
            } catch (e: LinkageError) {
                // For example UnsatisfiedLinkError when libflutter.so is missing.
                fail(what, e)
            }
        }

        /** Runs [block] and logs a failure without giving up on the engine. */
        private inline fun logged(what: String, block: () -> Unit) {
            try {
                block()
            } catch (e: Exception) {
                Log.w(TAG, "Wallpaper engine $engineId: failed to $what.", e)
            }
        }
    }

    private class ChoreographerScheduler : FrameScheduler {
        private val callbacks = HashMap<Runnable, Choreographer.FrameCallback>()

        override fun postFrame(callback: Runnable) {
            val frameCallback = callbacks.getOrPut(callback) { Choreographer.FrameCallback { callback.run() } }
            Choreographer.getInstance().postFrameCallback(frameCallback)
        }

        override fun removeFrame(callback: Runnable) {
            callbacks[callback]?.let { Choreographer.getInstance().removeFrameCallback(it) }
        }
    }

    private class HandlerScheduler(private val handler: Handler) : DelayScheduler {
        override fun postDelayed(callback: Runnable, delayMillis: Long) {
            handler.postDelayed(callback, delayMillis)
        }

        override fun remove(callback: Runnable) {
            handler.removeCallbacks(callback)
        }
    }

    companion object {
        /** Service meta-data naming the Dart entrypoint function. */
        const val META_ENTRYPOINT = "wallflower.entrypoint"

        /** Service meta-data naming the library that declares the entrypoint. */
        const val META_ENTRYPOINT_LIBRARY = "wallflower.entrypointLibrary"

        /** The entrypoint used when the service has no `wallflower.entrypoint` meta-data. */
        const val DEFAULT_ENTRYPOINT = "wallpaperMain"

        private const val TAG = "Wallflower"

        /** How long an engine must stay hidden before Flutter is paused. */
        private const val HIDE_SETTLE_MILLIS = 100L

        private const val FIRST_FRAME_WARNING_MILLIS = 5000L

        /** Tilt sampling period until Dart asks for another, about SENSOR_DELAY_GAME. */
        private const val TILT_SAMPLING_DEFAULT_MICROS = 20_000
    }
}
