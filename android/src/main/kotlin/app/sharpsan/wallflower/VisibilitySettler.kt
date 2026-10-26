package app.sharpsan.wallflower

/** Runs a callback after a delay. Backed by a main-thread `Handler` in production. */
internal interface DelayScheduler {
    fun postDelayed(callback: Runnable, delayMillis: Long)

    fun remove(callback: Runnable)
}

/**
 * Filters the visibility flaps that `WallpaperService` produces at startup and during
 * transitions (true, false, true within a few tens of milliseconds).
 *
 * Becoming visible applies at once, so the first frame isn't delayed. Becoming hidden applies
 * only if the engine stays hidden for [hideDelayMillis]; a visible event in between cancels it.
 * [apply] only sees real changes.
 */
internal class VisibilitySettler(
    private val scheduler: DelayScheduler,
    private val hideDelayMillis: Long,
    private val apply: (Boolean) -> Unit,
) {
    private var applied: Boolean? = null
    private var hidePending = false
    private val hideCallback = Runnable {
        hidePending = false
        if (applied != false) {
            applied = false
            apply(false)
        }
    }

    /** The last state passed to [apply], or null before the first one. */
    val current: Boolean?
        get() = applied

    fun onVisibilityChanged(visible: Boolean) {
        if (visible) {
            cancel()
            if (applied != true) {
                applied = true
                apply(true)
            }
        } else if (applied != false && !hidePending) {
            hidePending = true
            scheduler.postDelayed(hideCallback, hideDelayMillis)
        }
    }

    /** Cancels a pending hide without applying it. */
    fun cancel() {
        if (hidePending) {
            hidePending = false
            scheduler.remove(hideCallback)
        }
    }
}
