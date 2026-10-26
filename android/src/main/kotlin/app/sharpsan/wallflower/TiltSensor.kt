package app.sharpsan.wallflower

import android.content.Context
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.view.Surface
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.sqrt

/**
 * Reports which way is up, in screen coordinates, for tilt parallax.
 *
 * Uses the game rotation vector (gyroscope and accelerometer, no magnetometer, so no compass
 * jumps and less power), then the rotation vector, then the raw accelerometer. Each sample is the
 * world's up direction projected onto the screen's x and y axes, so both values are in -1..1 and
 * behave the same at any holding angle, plus the display rotation it was mapped with. Smoothing and
 * re-centering happen in Dart.
 *
 * Main thread only. Nothing runs until [start].
 */
internal class TiltSensor(
    context: Context,
    private val displayRotation: () -> Int,
    private val onSample: (x: Double, y: Double, rotation: Int) -> Unit,
) : SensorEventListener {
    private val sensorManager = context.getSystemService(Context.SENSOR_SERVICE) as SensorManager?
    private val sensor: Sensor? =
        sensorManager?.let {
            it.getDefaultSensor(Sensor.TYPE_GAME_ROTATION_VECTOR)
                ?: it.getDefaultSensor(Sensor.TYPE_ROTATION_VECTOR)
                ?: it.getDefaultSensor(Sensor.TYPE_ACCELEROMETER)
        }
    private var lastX = Double.NaN
    private var lastY = Double.NaN
    private var samplingPeriodMicros = 0
    private val rest = RestDetector(REST_AFTER_NANOS)

    // Re-registering restarts the sensor's fusion, which then reads up to a third of a degree away
    // from before and holds steady there. The first sample after it is the new reference, not
    // movement.
    private var rebase = false

    /** Whether the device has a usable sensor. */
    val available: Boolean
        get() = sensor != null

    var running = false
        private set

    fun start(samplingPeriodMicros: Int) {
        val manager = sensorManager ?: return
        if (running || sensor == null) return
        lastX = Double.NaN
        lastY = Double.NaN
        rebase = false
        rest.reset()
        this.samplingPeriodMicros = samplingPeriodMicros
        running = manager.registerListener(this, sensor, samplingPeriodMicros)
    }

    fun stop() {
        if (!running) return
        running = false
        sensorManager?.unregisterListener(this)
    }

    override fun onSensorChanged(event: SensorEvent) {
        val (x, y) = upVector(event) ?: return
        if (rebase) {
            rebase = false
            lastX = x
            lastY = y
            return
        }
        // Skip changes of less than about a tenth of a degree, so a resting phone sends nothing; Dart
        // smooths the steps. Comparing device axes gives the same answer as screen axes: the mapping
        // only swaps and negates them.
        val moved = !(abs(x - lastX) < MIN_CHANGE && abs(y - lastY) < MIN_CHANGE)
        if (rest.onSample(moved, event.timestamp)) reregister()
        if (!moved) return
        lastX = x
        lastY = y
        // Looked up only for samples that are sent: it costs more than everything else here.
        val rotation = displayRotation()
        val (screenX, screenY) = toScreen(x, y, rotation)
        onSample(screenX, screenY, rotation)
    }

    override fun onAccuracyChanged(sensor: Sensor, accuracy: Int) {}

    /**
     * Samples slowly while the phone rests: even with nothing sent, receiving samples at the full
     * rate costs a few percent of a core. The first sample that moves restores the full rate.
     */
    private fun reregister() {
        val manager = sensorManager ?: return
        manager.unregisterListener(this)
        rebase = true
        val period =
            if (rest.resting) max(samplingPeriodMicros, RESTING_SAMPLING_MICROS) else samplingPeriodMicros
        running = manager.registerListener(this, sensor, period)
    }

    /** The world's up direction in device coordinates, or null for an unusable sample. */
    private fun upVector(event: SensorEvent): Pair<Double, Double>? {
        val values = event.values
        if (event.sensor.type != Sensor.TYPE_ACCELEROMETER) return upFromRotationVector(values)
        // At rest the accelerometer reads the reaction to gravity, which points up.
        val norm = sqrt(values[0] * values[0] + values[1] * values[1] + values[2] * values[2])
        if (norm < 1e-3f) return null
        return values[0] / norm.toDouble() to values[1] / norm.toDouble()
    }

    companion object {
        private const val MIN_CHANGE = 2e-3
        private const val REST_AFTER_NANOS = 2_000_000_000L
        private const val RESTING_SAMPLING_MICROS = 100_000

        /**
         * The world's up direction in device coordinates from a rotation vector (a unit quaternion
         * x, y, z and optionally w): the x and y of the rotation matrix's third row, as
         * SensorManager.getRotationMatrixFromVector computes it, without building the matrix.
         */
        fun upFromRotationVector(values: FloatArray): Pair<Double, Double> {
            val x = values[0].toDouble()
            val y = values[1].toDouble()
            val z = values[2].toDouble()
            val w = if (values.size >= 4) values[3].toDouble() else sqrt(max(0.0, 1 - x * x - y * y - z * z))
            return 2 * (x * z - y * w) to 2 * (y * z + x * w)
        }

        /** Maps device-axis values to the current screen orientation. */
        fun toScreen(x: Double, y: Double, rotation: Int): Pair<Double, Double> =
            when (rotation) {
                Surface.ROTATION_90 -> -y to x
                Surface.ROTATION_180 -> -x to -y
                Surface.ROTATION_270 -> y to -x
                else -> x to y
            }
    }
}

/** Tracks whether the phone has been still for [restAfterNanos]. */
internal class RestDetector(private val restAfterNanos: Long) {
    var resting = false
        private set
    private var lastMoveNanos: Long? = null

    fun reset() {
        resting = false
        lastMoveNanos = null
    }

    /** Records a sample taken at [timestampNanos]. Returns true when [resting] changes. */
    fun onSample(moved: Boolean, timestampNanos: Long): Boolean {
        val lastMove = lastMoveNanos
        if (moved || lastMove == null) {
            lastMoveNanos = timestampNanos
            if (!resting) return false
            resting = false
            return true
        }
        if (resting || timestampNanos - lastMove < restAfterNanos) return false
        resting = true
        return true
    }
}
