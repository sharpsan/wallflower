package app.sharpsan.wallflower

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/** A [FrameScheduler] that runs frames only when the test says so. */
internal class FakeFrameScheduler : FrameScheduler {
    val posted = mutableListOf<Runnable>()

    override fun postFrame(callback: Runnable) {
        posted.add(callback)
    }

    override fun removeFrame(callback: Runnable) {
        posted.remove(callback)
    }

    fun runFrame() {
        val callbacks = posted.toList()
        posted.clear()
        callbacks.forEach { it.run() }
    }
}

internal class UpdateCoalescerTest {
    private val scheduler = FakeFrameScheduler()
    private val sent = mutableListOf<Map<String, Any?>>()
    private val coalescer = UpdateCoalescer(scheduler) { sent.add(it) }

    @Test
    fun coalescesUpdatesWithinOneFrame() {
        coalescer.put("offset", listOf(0.1, 0.0))
        coalescer.put("offset", listOf(0.2, 0.0))
        coalescer.put("zoom", 0.3)

        assertEquals(1, scheduler.posted.size, "one frame callback per frame")
        assertTrue(sent.isEmpty(), "nothing is sent before the frame")

        scheduler.runFrame()

        assertEquals(listOf(mapOf<String, Any?>("offset" to listOf(0.2, 0.0), "zoom" to 0.3)), sent)
    }

    @Test
    fun schedulesAgainAfterAFrame() {
        coalescer.put("zoom", 0.1)
        scheduler.runFrame()
        coalescer.put("zoom", 0.2)
        scheduler.runFrame()

        assertEquals(listOf(mapOf<String, Any?>("zoom" to 0.1), mapOf<String, Any?>("zoom" to 0.2)), sent)
    }

    @Test
    fun flushSendsImmediatelyAndCancelsTheFrame() {
        coalescer.put("visible", true)
        coalescer.flush()

        assertEquals(listOf(mapOf<String, Any?>("visible" to true)), sent)
        assertTrue(scheduler.posted.isEmpty())
    }

    @Test
    fun clearDropsPendingUpdates() {
        coalescer.put("zoom", 0.5)
        coalescer.clear()
        scheduler.runFrame()
        coalescer.flush()

        assertTrue(sent.isEmpty())
    }
}
