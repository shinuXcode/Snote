package com.snote.snote

import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.MethodChannel

/** Returns a one-frame native capture to the awaiting Flutter call. */
object ScreenCaptureBridge {
    private val mainHandler = Handler(Looper.getMainLooper())
    @Volatile private var pending: MethodChannel.Result? = null

    @Synchronized
    fun attach(result: MethodChannel.Result): Boolean {
        if (pending != null) return false
        pending = result
        return true
    }

    fun complete(bytes: ByteArray?, error: String?) {
        mainHandler.post {
            val callback = synchronized(this) {
                val current = pending
                pending = null
                current
            }
            if (error != null) callback?.error("screen_capture_failed", error, null)
            else callback?.success(bytes)
        }
    }
}
