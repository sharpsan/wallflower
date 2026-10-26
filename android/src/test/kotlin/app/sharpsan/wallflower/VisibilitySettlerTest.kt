package app.sharpsan.wallflower

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

/** A [DelayScheduler] with a manual clock. */
internal class FakeDelayScheduler : DelayScheduler {
    private var now = 0L
    private val pending = mutableListOf<Pair<Long, Runnable>>()

    override fun postDelayed(callback: Runnable, delayMillis: Long) {
        pending.add(now + delayMillis to callback)
    }

    override fun remove(callback: Runnable) {
        pending.removeAll { it.second === callback }
    }

    fun advance(millis: Long) {
        now += millis
        val due = pending.filter { it.first <= now }
        pending.removeAll(due)
        due.forEach { it.second.run() }
    }
}

internal class VisibilitySettlerTest {
    private val scheduler = FakeDelayScheduler()
    private val applied = mutableListOf<Boolean>()
    private val settler = VisibilitySettler(scheduler, 100) { applied.add(it) }

    @Test
    fun becomingVisibleAppliesAtOnce() {
        settler.onVisibilityChanged(true)

        assertEquals(listOf(true), applied)
    }

    @Test
    fun startupFlapIsIgnored() {
        // What WallpaperService sends when an engine starts: true, false, true within ~30 ms.
        settler.onVisibilityChanged(true)
        settler.onVisibilityChanged(false)
        scheduler.advance(30)
        settler.onVisibilityChanged(true)
        scheduler.advance(500)

        assertEquals(listOf(true), applied)
    }

    @Test
    fun hidingAppliesAfterTheDelay() {
        settler.onVisibilityChanged(true)
        settler.onVisibilityChanged(false)
        scheduler.advance(99)
        assertEquals(listOf(true), applied)

        scheduler.advance(1)
        assertEquals(listOf(true, false), applied)
        assertEquals(false, settler.current)
    }

    @Test
    fun repeatedEventsDoNotRepeatChanges() {
        settler.onVisibilityChanged(true)
        settler.onVisibilityChanged(true)
        settler.onVisibilityChanged(false)
        settler.onVisibilityChanged(false)
        scheduler.advance(100)
        settler.onVisibilityChanged(false)
        scheduler.advance(100)

        assertEquals(listOf(true, false), applied)
    }

    @Test
    fun cancelDropsAPendingHide() {
        settler.onVisibilityChanged(true)
        settler.onVisibilityChanged(false)
        settler.cancel()
        scheduler.advance(1000)

        assertEquals(listOf(true), applied)
    }

    @Test
    fun startsUnknown() {
        assertNull(settler.current)
    }
}
