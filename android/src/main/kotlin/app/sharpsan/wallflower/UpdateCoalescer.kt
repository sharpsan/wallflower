package app.sharpsan.wallflower

/** Runs a callback once on the next frame. Backed by `Choreographer` in production. */
internal interface FrameScheduler {
    fun postFrame(callback: Runnable)

    fun removeFrame(callback: Runnable)
}

/**
 * Collects state changes and sends them as one map per frame.
 *
 * Launchers report page offsets and zoom once per frame or more, from separate binder calls.
 * Without coalescing, a fast swipe sends several channel messages per frame and Dart rebuilds
 * for each of them.
 */
internal class UpdateCoalescer(
    private val scheduler: FrameScheduler,
    private val send: (Map<String, Any?>) -> Unit,
) {
    private val pending = LinkedHashMap<String, Any?>()
    private var scheduled = false
    private val flushCallback = Runnable { flush() }

    /** Records the latest [value] for [key] and schedules a flush if none is pending. */
    fun put(key: String, value: Any?) {
        pending[key] = value
        if (!scheduled) {
            scheduled = true
            scheduler.postFrame(flushCallback)
        }
    }

    /** Sends everything pending now. */
    fun flush() {
        if (scheduled) {
            scheduled = false
            scheduler.removeFrame(flushCallback)
        }
        if (pending.isEmpty()) return
        val update = LinkedHashMap(pending)
        pending.clear()
        send(update)
    }

    /** Drops everything pending, for example because a full snapshot replaces it. */
    fun clear() {
        pending.clear()
        if (scheduled) {
            scheduled = false
            scheduler.removeFrame(flushCallback)
        }
    }
}
