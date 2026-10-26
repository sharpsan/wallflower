package app.sharpsan.wallflower

import android.content.Context
import android.os.Build
import android.view.RoundedCorner
import android.view.ViewConfiguration
import android.view.WindowInsets
import io.flutter.embedding.engine.renderer.FlutterRenderer
import io.flutter.embedding.engine.renderer.FlutterRenderer.DisplayFeature
import io.flutter.embedding.engine.renderer.FlutterRenderer.DisplayFeatureState
import io.flutter.embedding.engine.renderer.FlutterRenderer.DisplayFeatureType

/**
 * Builds Flutter viewport metrics for a wallpaper surface: size, density, system-bar padding and
 * gesture insets. The insets mapping follows `FlutterView.onApplyWindowInsets`, so `SafeArea` and
 * `MediaQuery` behave as they do in an app.
 */
internal class ViewportMetricsFactory {
    val metrics = FlutterRenderer.ViewportMetrics()

    /** True once a surface size is known; Flutter ignores metrics without one. */
    val hasSize: Boolean
        get() = metrics.width > 0 && metrics.height > 0

    fun setSize(width: Int, height: Int) {
        metrics.width = width
        metrics.height = height
        metrics.minWidth = width
        metrics.maxWidth = width
        metrics.minHeight = height
        metrics.maxHeight = height
    }

    /** Reads density and touch slop from [context], ideally the engine's display context. */
    fun setDisplay(context: Context) {
        metrics.devicePixelRatio = context.resources.displayMetrics.density
        metrics.physicalTouchSlop = ViewConfiguration.get(context).scaledTouchSlop
    }

    fun setInsets(insets: WindowInsets) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            applyInsetsApi30(insets)
        } else {
            applyLegacyInsets(insets)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            applyCutouts(insets)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            applyRoundedCorners(insets)
        }
    }

    /** Reports camera and sensor cutouts as display features (`MediaQuery.displayFeatures`). */
    private fun applyCutouts(insets: WindowInsets) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.P) return
        val cutouts =
            insets.displayCutout?.boundingRects.orEmpty().map {
                DisplayFeature(it, DisplayFeatureType.CUTOUT, DisplayFeatureState.UNKNOWN)
            }
        metrics.setDisplayCutouts(cutouts)
    }

    private fun applyInsetsApi30(insets: WindowInsets) {
        val bars = insets.getInsets(WindowInsets.Type.systemBars())
        var top = bars.top
        var right = bars.right
        var bottom = bars.bottom
        var left = bars.left
        // Merge the display cutout into the padding, as FlutterView does.
        insets.displayCutout?.let { cutout ->
            val waterfall = cutout.waterfallInsets
            top = maxOf(top, waterfall.top, cutout.safeInsetTop)
            right = maxOf(right, waterfall.right, cutout.safeInsetRight)
            bottom = maxOf(bottom, waterfall.bottom, cutout.safeInsetBottom)
            left = maxOf(left, waterfall.left, cutout.safeInsetLeft)
        }
        metrics.viewPaddingTop = top
        metrics.viewPaddingRight = right
        metrics.viewPaddingBottom = bottom
        metrics.viewPaddingLeft = left

        val gestures = insets.getInsets(WindowInsets.Type.systemGestures())
        metrics.systemGestureInsetTop = gestures.top
        metrics.systemGestureInsetRight = gestures.right
        metrics.systemGestureInsetBottom = gestures.bottom
        metrics.systemGestureInsetLeft = gestures.left
    }

    @Suppress("DEPRECATION")
    private fun applyLegacyInsets(insets: WindowInsets) {
        metrics.viewPaddingTop = insets.systemWindowInsetTop
        metrics.viewPaddingRight = insets.systemWindowInsetRight
        metrics.viewPaddingBottom = insets.systemWindowInsetBottom
        metrics.viewPaddingLeft = insets.systemWindowInsetLeft
        if (Build.VERSION.SDK_INT == Build.VERSION_CODES.Q) {
            val gestures = insets.systemGestureInsets
            metrics.systemGestureInsetTop = gestures.top
            metrics.systemGestureInsetRight = gestures.right
            metrics.systemGestureInsetBottom = gestures.bottom
            metrics.systemGestureInsetLeft = gestures.left
        }
    }

    private fun applyRoundedCorners(insets: WindowInsets) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return
        metrics.displayCornerRadiusTopLeft = insets.radius(RoundedCorner.POSITION_TOP_LEFT)
        metrics.displayCornerRadiusTopRight = insets.radius(RoundedCorner.POSITION_TOP_RIGHT)
        metrics.displayCornerRadiusBottomRight = insets.radius(RoundedCorner.POSITION_BOTTOM_RIGHT)
        metrics.displayCornerRadiusBottomLeft = insets.radius(RoundedCorner.POSITION_BOTTOM_LEFT)
    }

    private fun WindowInsets.radius(position: Int): Int =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) getRoundedCorner(position)?.radius ?: 0 else 0
}
