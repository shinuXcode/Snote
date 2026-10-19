package com.snote.snote

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.graphics.Bitmap
import android.graphics.PixelFormat
import android.hardware.display.DisplayManager
import android.hardware.display.VirtualDisplay
import android.media.Image
import android.media.ImageReader
import android.media.projection.MediaProjection
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.os.Handler
import android.os.HandlerThread
import android.os.IBinder
import android.util.DisplayMetrics
import android.view.WindowManager
import java.io.ByteArrayOutputStream
import java.nio.ByteBuffer

/** Captures one approved display frame in memory and returns PNG bytes to Flutter. */
class ScreenCaptureService : Service() {
    companion object {
        const val EXTRA_RESULT_CODE = "projection_result_code"
        const val EXTRA_RESULT_DATA = "projection_result_data"
        private const val NOTIFICATION_ID = 49202
        private const val CHANNEL_ID = "snote_screen_capture"
    }

    private var projection: MediaProjection? = null
    private var virtualDisplay: VirtualDisplay? = null
    private var imageReader: ImageReader? = null
    private var thread: HandlerThread? = null
    private var worker: Handler? = null
    private var finished = false
    private var tries = 0

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        try {
            createNotificationChannel()
            val notification = buildNotification()
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                startForeground(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION)
            } else {
                startForeground(NOTIFICATION_ID, notification)
            }

            val resultCode = intent?.getIntExtra(EXTRA_RESULT_CODE, 0) ?: 0
            val data = projectionIntent(intent)
            if (resultCode != android.app.Activity.RESULT_OK || data == null) {
                finishWithError("Android did not provide screen capture permission.")
                return START_NOT_STICKY
            }

            val manager = getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
            projection = manager.getMediaProjection(resultCode, data)
            thread = HandlerThread("SnoteScreenCapture").also { it.start() }
            worker = Handler(thread!!.looper)
            val metrics = DisplayMetrics()
            @Suppress("DEPRECATION")
            (getSystemService(Context.WINDOW_SERVICE) as WindowManager).defaultDisplay.getRealMetrics(metrics)
            val width = metrics.widthPixels
            val height = metrics.heightPixels
            if (width <= 0 || height <= 0) {
                finishWithError("The display reports invalid dimensions.")
                return START_NOT_STICKY
            }

            imageReader = ImageReader.newInstance(width, height, PixelFormat.RGBA_8888, 3)
            projection?.registerCallback(object : MediaProjection.Callback() {
                override fun onStop() {
                    if (!finished) finishWithError("Screen capture permission was stopped.")
                }
            }, worker)
            virtualDisplay = projection?.createVirtualDisplay(
                "SnoteInMemoryCapture",
                width,
                height,
                metrics.densityDpi,
                DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR,
                imageReader!!.surface,
                null,
                worker
            )
            imageReader?.setOnImageAvailableListener({ reader -> captureOneFrame(reader, width, height) }, worker)
            worker?.postDelayed({ captureOneFrame(imageReader, width, height) }, 550L)
        } catch (error: Exception) {
            finishWithError(error.message ?: "Unable to capture the display.")
        }
        return START_NOT_STICKY
    }

    @Suppress("DEPRECATION")
    private fun projectionIntent(intent: Intent?): Intent? {
        if (intent == null) return null
        return if (Build.VERSION.SDK_INT >= 33) {
            intent.getParcelableExtra(EXTRA_RESULT_DATA, Intent::class.java)
        } else {
            intent.getParcelableExtra(EXTRA_RESULT_DATA)
        }
    }

    private fun captureOneFrame(reader: ImageReader?, width: Int, height: Int) {
        if (finished || reader == null) return
        var image: Image? = null
        try {
            image = reader.acquireLatestImage()
            if (image == null) {
                tries++
                if (tries < 18) worker?.postDelayed({ captureOneFrame(reader, width, height) }, 120L)
                else finishWithError("No display frame arrived before the capture timed out.")
                return
            }
            val plane = image.planes[0]
            val paddedWidth = plane.rowStride / plane.pixelStride
            val buffer: ByteBuffer = plane.buffer
            buffer.rewind()
            val padded = Bitmap.createBitmap(paddedWidth, height, Bitmap.Config.ARGB_8888)
            padded.copyPixelsFromBuffer(buffer)
            val bitmap = Bitmap.createBitmap(padded, 0, 0, width, height)
            padded.recycle()
            val png = ByteArrayOutputStream().use { output ->
                bitmap.compress(Bitmap.CompressFormat.PNG, 100, output)
                output.toByteArray()
            }
            bitmap.recycle()
            if (png.isEmpty()) {
                finishWithError("The captured display frame was empty.")
            } else {
                finished = true
                ScreenCaptureBridge.complete(png, null)
                releaseCaptureResources()
                stopSelf()
            }
        } catch (error: Exception) {
            finishWithError(error.message ?: "Could not convert the captured frame.")
        } finally {
            image?.close()
        }
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            nm.createNotificationChannel(NotificationChannel(
                CHANNEL_ID, "Snote screen capture", NotificationManager.IMPORTANCE_LOW
            ))
        }
    }

    private fun buildNotification(): Notification {
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        return builder.setSmallIcon(android.R.drawable.ic_menu_camera)
            .setContentTitle("Snote is capturing the screen")
            .setContentText("The frame will be inserted into the note in memory.")
            .setOngoing(true)
            .build()
    }

    private fun finishWithError(message: String) {
        if (finished) return
        finished = true
        ScreenCaptureBridge.complete(null, message)
        releaseCaptureResources()
        stopSelf()
    }

    private fun releaseCaptureResources() {
        try { imageReader?.setOnImageAvailableListener(null, null) } catch (_: Exception) {}
        try { virtualDisplay?.release() } catch (_: Exception) {}
        virtualDisplay = null
        try { imageReader?.close() } catch (_: Exception) {}
        imageReader = null
        try { projection?.stop() } catch (_: Exception) {}
        projection = null
        try { thread?.quitSafely() } catch (_: Exception) {}
        thread = null
        worker = null
        try { stopForeground(STOP_FOREGROUND_REMOVE) } catch (_: Exception) {}
    }

    override fun onDestroy() {
        if (!finished) {
            finished = true
            ScreenCaptureBridge.complete(null, "Screen capture was interrupted.")
        }
        releaseCaptureResources()
        super.onDestroy()
    }
}
