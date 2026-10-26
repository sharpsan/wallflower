package app.sharpsan.wallflower

import android.content.Context
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineGroup
import io.flutter.embedding.engine.dart.DartExecutor

/**
 * Owns the process-wide [FlutterEngineGroup] that wallpaper engines are spawned from.
 *
 * Spawned engines share the group's Dart VM snapshot and GPU context, which makes the second
 * and later engines (picker preview, a second display) much cheaper than the first. Main thread
 * only.
 */
internal object EngineHost {
    private var group: FlutterEngineGroup? = null

    /**
     * Spawns an engine and starts [functionName] (in [libraryUri], or the app's main library when
     * null). Creating the group initializes `FlutterLoader` synchronously on first use.
     */
    fun spawn(context: Context, functionName: String, libraryUri: String?): FlutterEngine {
        val appContext = context.applicationContext
        val group = group ?: FlutterEngineGroup(appContext).also { group = it }
        val bundlePath = FlutterInjector.instance().flutterLoader().findAppBundlePath()
        val entrypoint =
            if (libraryUri.isNullOrEmpty()) {
                DartExecutor.DartEntrypoint(bundlePath, functionName)
            } else {
                DartExecutor.DartEntrypoint(bundlePath, libraryUri, functionName)
            }
        return WallpaperHub.spawningWallpaperEngine {
            group.createAndRunEngine(FlutterEngineGroup.Options(appContext).setDartEntrypoint(entrypoint))
        }
    }
}
