package app.sharpsan.wallflower

import android.Manifest
import android.content.ComponentName
import android.content.Context
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.os.Build

/** Finds this app's [FlutterWallpaperService] declarations in the manifest. */
internal object WallpaperServices {
    private var cached: List<ComponentName>? = null

    /** All wallflower wallpaper services the app declares, in manifest order. */
    fun all(context: Context): List<ComponentName> =
        cached ?: scan(context).also { cached = it }

    /**
     * The services [service] names: all of them when null, otherwise the one whose class name is
     * [service], ends with `.service`, or (for `.Name`) ends with it. Empty if nothing matches.
     */
    fun resolve(context: Context, service: String?): List<ComponentName> {
        val all = all(context)
        if (service.isNullOrEmpty()) return all
        return all.filter {
            it.className == service ||
                it.className.endsWith(if (service.startsWith(".")) service else ".$service")
        }
    }

    private fun scan(context: Context): List<ComponentName> {
        val packageManager = context.packageManager
        val info: PackageInfo =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                packageManager.getPackageInfo(
                    context.packageName,
                    PackageManager.PackageInfoFlags.of(PackageManager.GET_SERVICES.toLong()),
                )
            } else {
                @Suppress("DEPRECATION")
                packageManager.getPackageInfo(context.packageName, PackageManager.GET_SERVICES)
            }
        return info.services
            .orEmpty()
            .filter { it.permission == Manifest.permission.BIND_WALLPAPER && isWallflower(context, it.name) }
            .map { ComponentName(it.packageName, it.name) }
    }

    private fun isWallflower(context: Context, className: String): Boolean =
        try {
            FlutterWallpaperService::class.java.isAssignableFrom(
                Class.forName(className, false, context.classLoader)
            )
        } catch (e: ClassNotFoundException) {
            false
        }
}
