package app.sharpsan.wallflower

import android.app.Activity
import android.app.WallpaperManager
import android.content.ActivityNotFoundException
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Build
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * The app-side `LiveWallpaper` API: checks and opens the wallpaper, stores its config, and
 * exchanges messages with running wallpaper engines.
 *
 * Flutter registers it with every engine in the app, including wallpaper engines. Only the
 * app's own engines receive messages that wallpapers send to the app.
 */
class LiveWallpaperPlugin : FlutterPlugin, ActivityAware, MethodChannel.MethodCallHandler {
    private var context: Context? = null
    private var channel: MethodChannel? = null
    private var activity: Activity? = null
    private var endpoint: WallpaperHub.AppEndpoint? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        val channel = MethodChannel(binding.binaryMessenger, CHANNEL).also { it.setMethodCallHandler(this) }
        this.channel = channel
        if (!WallpaperHub.spawningWallpaperEngine) {
            endpoint =
                WallpaperHub.AppEndpoint { name, data ->
                    channel.invokeMethod(METHOD_MESSAGE, mapOf(KEY_NAME to name, KEY_DATA to data))
                    true
                }.also { WallpaperHub.register(it) }
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        endpoint?.let { WallpaperHub.unregister(it) }
        endpoint = null
        channel?.setMethodCallHandler(null)
        channel = null
        context = null
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activity = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity
    }

    override fun onDetachedFromActivity() {
        activity = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        val context = context ?: return result.error("detached", "The plugin is detached.", null)
        val service = call.argument<String>(KEY_SERVICE)
        val services = WallpaperServices.resolve(context, service)
        if (services.isEmpty()) {
            return result.error(
                "no_service",
                if (service == null) {
                    "The app declares no FlutterWallpaperService with the BIND_WALLPAPER permission."
                } else {
                    "No FlutterWallpaperService named '$service' is declared in the manifest."
                },
                null,
            )
        }
        val classNames = services.map { it.className }
        when (call.method) {
            "isActive" -> result.success(isActive(context, services))
            "openPicker" -> result.success(openPicker(context, services.first()))
            "getConfig" -> result.success(WallpaperHub.configJson(context, classNames.first()))
            "setConfig" -> {
                WallpaperHub.setConfigJson(context, classNames, call.argument<String>(KEY_CONFIG))
                result.success(null)
            }
            "send" -> {
                val name = call.argument<String>(KEY_NAME)
                    ?: return result.error("bad_args", "'name' is required.", null)
                result.success(WallpaperHub.sendToWallpapers(classNames, name, call.argument<Any?>(KEY_DATA)))
            }
            else -> result.notImplemented()
        }
    }

    private fun isActive(context: Context, services: List<ComponentName>): Boolean {
        val manager = WallpaperManager.getInstance(context)
        val active = mutableListOf(manager.wallpaperInfo?.component)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            active += manager.getWallpaperInfo(WallpaperManager.FLAG_LOCK)?.component
        }
        return active.any { it != null && it in services }
    }

    /** Opens the system preview for [service], or the live wallpaper list if that's missing. */
    private fun openPicker(context: Context, service: ComponentName): Boolean {
        val preview =
            Intent(WallpaperManager.ACTION_CHANGE_LIVE_WALLPAPER)
                .putExtra(WallpaperManager.EXTRA_LIVE_WALLPAPER_COMPONENT, service)
        return start(context, preview) || start(context, Intent(WallpaperManager.ACTION_LIVE_WALLPAPER_CHOOSER))
    }

    private fun start(context: Context, intent: Intent): Boolean =
        try {
            val activity = activity
            if (activity != null) {
                activity.startActivity(intent)
            } else {
                context.startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            }
            true
        } catch (e: ActivityNotFoundException) {
            false
        }

    private companion object {
        const val CHANNEL = "wallflower/app"
        const val METHOD_MESSAGE = "message"
        const val KEY_SERVICE = "service"
        const val KEY_CONFIG = "config"
        const val KEY_NAME = "name"
        const val KEY_DATA = "data"
    }
}
