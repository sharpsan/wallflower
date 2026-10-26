package app.sharpsan.wallflower

import android.view.Surface
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.sin
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

internal class TiltSensorTest {
    @Test
    fun deviceAxesFollowTheScreenRotation() {
        // The up vector of a phone whose right edge is raised: positive device x.
        val x = 0.3
        val y = 0.8
        assertEquals(x to y, TiltSensor.toScreen(x, y, Surface.ROTATION_0))
        assertEquals(-y to x, TiltSensor.toScreen(x, y, Surface.ROTATION_90))
        assertEquals(-x to -y, TiltSensor.toScreen(x, y, Surface.ROTATION_180))
        assertEquals(y to -x, TiltSensor.toScreen(x, y, Surface.ROTATION_270))
    }

    @Test
    fun upVectorFromRotationVector() {
        // Lying flat, face up: up is straight out of the screen.
        assertUp(0.0, 0.0, TiltSensor.upFromRotationVector(floatArrayOf(0f, 0f, 0f, 1f)))
        // Stood upright (turned 90 degrees about the device x axis): up is the top edge.
        assertUp(0.0, 1.0, TiltSensor.upFromRotationVector(quaternion(1.0, 0.0, PI / 2)))
        // Turned 90 degrees about the device y axis: the right edge points down.
        assertUp(-1.0, 0.0, TiltSensor.upFromRotationVector(quaternion(0.0, 1.0, PI / 2)))
        // Older sensors leave out w; it follows from the unit length.
        val upright = quaternion(1.0, 0.0, PI / 6)
        assertUp(0.0, 0.5, TiltSensor.upFromRotationVector(upright.copyOf(3)))
    }

    @Test
    fun restsAfterStillnessAndWakesOnMovement() {
        val rest = RestDetector(restAfterNanos = 1_000)
        assertFalse(rest.onSample(moved = false, timestampNanos = 0))
        assertFalse(rest.onSample(moved = false, timestampNanos = 999))
        assertTrue(rest.onSample(moved = false, timestampNanos = 1_000))
        assertTrue(rest.resting)
        assertFalse(rest.onSample(moved = false, timestampNanos = 5_000))

        assertTrue(rest.onSample(moved = true, timestampNanos = 5_100))
        assertFalse(rest.resting)
        assertFalse(rest.onSample(moved = false, timestampNanos = 6_000))
        assertTrue(rest.onSample(moved = false, timestampNanos = 6_100))

        rest.reset()
        assertFalse(rest.resting)
        // The first sample after a reset starts the clock.
        assertFalse(rest.onSample(moved = false, timestampNanos = 50_000))
        assertFalse(rest.onSample(moved = false, timestampNanos = 50_500))
    }

    /** A rotation of [angle] about the device axis (ax, ay, 0), as x, y, z, w. */
    private fun quaternion(ax: Double, ay: Double, angle: Double): FloatArray {
        val s = sin(angle / 2)
        return floatArrayOf((ax * s).toFloat(), (ay * s).toFloat(), 0f, cos(angle / 2).toFloat())
    }

    private fun assertUp(x: Double, y: Double, actual: Pair<Double, Double>) {
        assertEquals(x, actual.first, 1e-6)
        assertEquals(y, actual.second, 1e-6)
    }
}
