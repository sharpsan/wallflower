package app.sharpsan.wallflower

import kotlin.test.Test
import kotlin.test.assertEquals

internal class WallpaperProtocolTest {
    @Test
    fun stepOfASinglePageLauncherBecomesZero() {
        // Pixel Launcher reports 1 / (pages - 1), which is Infinity with one page.
        assertEquals(0.0, WallpaperProtocol.sanitizeStep(Float.POSITIVE_INFINITY))
        assertEquals(0.0, WallpaperProtocol.sanitizeStep(Float.NaN))
        assertEquals(0.0, WallpaperProtocol.sanitizeStep(-1f))
        assertEquals(0.0, WallpaperProtocol.sanitizeStep(0f))
    }

    @Test
    fun validStepsPassThrough() {
        assertEquals(1.0 / 3, WallpaperProtocol.sanitizeStep(1f / 3), 1e-6)
        assertEquals(0.5, WallpaperProtocol.sanitizeStep(0.5f))
    }

    @Test
    fun offsetsAndZoomAreClamped() {
        assertEquals(0.0, WallpaperProtocol.sanitizeOffset(-0.2f))
        assertEquals(1.0, WallpaperProtocol.sanitizeOffset(1.4f))
        assertEquals(0.0, WallpaperProtocol.sanitizeOffset(Float.NaN))
        assertEquals(0.25, WallpaperProtocol.sanitizeOffset(0.25f))
        assertEquals(0.33, WallpaperProtocol.sanitizeZoom(0.33f), 1e-6)
        assertEquals(0.0, WallpaperProtocol.sanitizeZoom(Float.NEGATIVE_INFINITY))
    }
}
