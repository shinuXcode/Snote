#!/usr/bin/env python3
"""Configure generated Android runner for in-memory, consent-based screen capture."""
from pathlib import Path

android = Path("android")
main_candidates = list((android / "app/src/main/kotlin").rglob("MainActivity.kt"))
if len(main_candidates) != 1:
    raise SystemExit(f"Expected exactly one generated MainActivity.kt, found {len(main_candidates)}")
main_activity = main_candidates[0]
package = main_activity.read_text().splitlines()[0].removeprefix("package ").strip()
if not package or "." not in package:
    raise SystemExit(f"Cannot infer Kotlin package from {main_activity}")

kotlin = r'''package __PACKAGE__

import android.app.Activity
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
import android.os.Looper
import android.util.DisplayMetrics
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream

private const val SCREEN_CAPTURE_CHANNEL = "com.snote/screen_capture"
private const val REQUEST_SCREEN_CAPTURE = 7318
private const val EXTRA_RESULT_CODE = "snote.resultCode"
private const val EXTRA_CAPTURE_DATA = "snote.captureData"

private object SnoteCaptureResult {
    @Volatile var callback: ((ByteArray?, String?) -> Unit)? = null
    fun complete(bytes: ByteArray?, error: String?) {
        callback?.invoke(bytes, error)
    }
}

class MainActivity : FlutterActivity() {
    private var pendingCaptureResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SCREEN_CAPTURE_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "captureDisplay" -> requestScreenCapture(result)
                    else -> result.notImplemented()
                }
            }
    }

    private fun requestScreenCapture(result: MethodChannel.Result) {
        if (pendingCaptureResult != null) {
            result.error("capture_in_progress", "A screen capture is already running.", null)
            return
        }
        val manager = getSystemService(Context.MEDIA_PROJECTION_SERVICE) as? MediaProjectionManager
        if (manager == null) {
            result.error("capture_unavailable", "Android screen capture is not available on this device.", null)
            return
        }
        pendingCaptureResult = result
        try {
            startActivityForResult(manager.createScreenCaptureIntent(), REQUEST_SCREEN_CAPTURE)
        } catch (error: Exception) {
            pendingCaptureResult = null
            result.error("capture_start_failed", error.message, null)
        }
    }

    @Deprecated("Android screen-capture consent result")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode != REQUEST_SCREEN_CAPTURE) {
            super.onActivityResult(requestCode, resultCode, data)
            return
        }
        val result = pendingCaptureResult
        if (result == null) return
        if (resultCode != Activity.RESULT_OK || data == null) {
            pendingCaptureResult = null
            result.error("capture_cancelled", "Screen capture was cancelled.", null)
            return
        }

        SnoteCaptureResult.callback = { bytes, error ->
            runOnUiThread {
                val pending = pendingCaptureResult
                pendingCaptureResult = null
                SnoteCaptureResult.callback = null
                if (pending != null) {
                    if (bytes != null) pending.success(bytes)
                    else pending.error("capture_failed", error ?: "Could not capture the display.", null)
                }
            }
        }

        val serviceIntent = Intent(this, SnoteScreenCaptureService::class.java)
            .putExtra(EXTRA_RESULT_CODE, resultCode)
            .putExtra(EXTRA_CAPTURE_DATA, data)
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                ContextCompat.startForegroundService(this, serviceIntent)
            } else {
                startService(serviceIntent)
            }
        } catch (error: Exception) {
            pendingCaptureResult = null
            SnoteCaptureResult.callback = null
            result.error("capture_service_failed", error.message, null)
        }
    }

    override fun onDestroy() {
        pendingCaptureResult?.error("capture_interrupted", "Screen capture was interrupted.", null)
        pendingCaptureResult = null
        SnoteCaptureResult.callback = null
        super.onDestroy()
    }
}

class SnoteScreenCaptureService : Service() {
    private val mainHandler = Handler(Looper.getMainLooper())
    private var captureThread: HandlerThread? = null
    private var projection: MediaProjection? = null
    private var projectionCallback: MediaProjection.Callback? = null
    private var virtualDisplay: VirtualDisplay? = null
    private var imageReader: ImageReader? = null
    private var finished = false
    private var released = false

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent == null) {
            stopSelf(startId)
            return START_NOT_STICKY
        }
        startCaptureNotification()
        val resultCode = intent.getIntExtra(EXTRA_RESULT_CODE, Activity.RESULT_CANCELED)
        @Suppress("DEPRECATION")
        val data: Intent? = if (Build.VERSION.SDK_INT >= 33) {
            intent.getParcelableExtra(EXTRA_CAPTURE_DATA, Intent::class.java)
        } else {
            intent.getParcelableExtra(EXTRA_CAPTURE_DATA)
        }
        if (resultCode != Activity.RESULT_OK || data == null) {
            finishCapture(null, "Android did not return screen capture permission.")
            return START_NOT_STICKY
        }

        try {
            val manager = getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
            projection = manager.getMediaProjection(resultCode, data)
                ?: throw IllegalStateException("Android did not create a screen capture session.")

            val metrics = DisplayMetrics()
            @Suppress("DEPRECATION")
            windowManager.defaultDisplay.getRealMetrics(metrics)
            val width = metrics.widthPixels.coerceAtLeast(1)
            val height = metrics.heightPixels.coerceAtLeast(1)
            val reader = ImageReader.newInstance(width, height, PixelFormat.RGBA_8888, 2)
            imageReader = reader

            projectionCallback = object : MediaProjection.Callback() {
                override fun onStop() {
                    if (!finished) finishCapture(null, "Android stopped the screen capture session.")
                }
            }
            projection?.registerCallback(projectionCallback!!, mainHandler)

            captureThread = HandlerThread("SnoteScreenCaptureWorker").also { it.start() }
            reader.setOnImageAvailableListener({ source ->
                if (finished) return@setOnImageAvailableListener
                val image = source.acquireLatestImage() ?: return@setOnImageAvailableListener
                try {
                    finishCapture(encodeImage(image, width, height), null)
                } catch (error: Exception) {
                    finishCapture(null, error.message ?: "Could not encode the captured display.")
                } finally {
                    image.close()
                }
            }, Handler(captureThread!!.looper))

            virtualDisplay = projection?.createVirtualDisplay(
                "SnoteInMemoryCapture",
                width,
                height,
                metrics.densityDpi.coerceAtLeast(1),
                DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR,
                reader.surface,
                null,
                mainHandler
            ) ?: throw IllegalStateException("Android could not create a capture display.")

            mainHandler.postDelayed({
                if (!finished) finishCapture(null, "Timed out waiting for the screen image.")
            }, 8000L)
        } catch (error: Exception) {
            finishCapture(null, error.message ?: "Could not start Android screen capture.")
        }
        return START_NOT_STICKY
    }

    private fun encodeImage(image: Image, width: Int, height: Int): ByteArray {
        val plane = image.planes.firstOrNull()
            ?: throw IllegalStateException("Screen capture returned no image plane.")
        val pixelStride = plane.pixelStride.coerceAtLeast(1)
        val rowStride = plane.rowStride
        val paddedWidth = (width + ((rowStride - pixelStride * width).coerceAtLeast(0) / pixelStride))
            .coerceAtLeast(width)
        val padded = Bitmap.createBitmap(paddedWidth, height, Bitmap.Config.ARGB_8888)
        try {
            padded.copyPixelsFromBuffer(plane.buffer)
            val cropped = if (paddedWidth == width) padded else Bitmap.createBitmap(padded, 0, 0, width, height)
            try {
                val stream = ByteArrayOutputStream()
                if (!cropped.compress(Bitmap.CompressFormat.PNG, 100, stream)) {
                    throw IllegalStateException("Could not encode the screenshot as PNG.")
                }
                return stream.toByteArray()
            } finally {
                if (cropped !== padded) cropped.recycle()
            }
        } finally {
            padded.recycle()
        }
    }

    private fun startCaptureNotification() {
        val channelId = "snote_screen_capture"
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(channelId, "Snote screen capture", NotificationManager.IMPORTANCE_LOW)
            (getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager).createNotificationChannel(channel)
        }
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, channelId)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        val notification = builder
            .setContentTitle("Snote screenshot")
            .setContentText("Capturing the display to insert into the active note")
            .setSmallIcon(android.R.drawable.ic_menu_camera)
            .setOngoing(true)
            .build()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(7319, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION)
        } else {
            startForeground(7319, notification)
        }
    }

    private fun finishCapture(bytes: ByteArray?, error: String?) {
        if (finished) return
        finished = true
        SnoteCaptureResult.complete(bytes, error)
        releaseCapture()
    }

    @Suppress("DEPRECATION")
    private fun releaseCapture() {
        if (released) return
        released = true
        try { imageReader?.setOnImageAvailableListener(null, null) } catch (_: Exception) {}
        try { virtualDisplay?.release() } catch (_: Exception) {}
        try { projectionCallback?.let { projection?.unregisterCallback(it) } } catch (_: Exception) {}
        try { projection?.stop() } catch (_: Exception) {}
        try { imageReader?.close() } catch (_: Exception) {}
        try { captureThread?.quitSafely() } catch (_: Exception) {}
        captureThread = null
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) stopForeground(STOP_FOREGROUND_REMOVE)
        else stopForeground(true)
        stopSelf()
    }

    override fun onDestroy() {
        if (!finished) {
            finished = true
            SnoteCaptureResult.complete(null, "Screen capture service was stopped.")
        }
        releaseCapture()
        super.onDestroy()
    }
}
'''.replace("__PACKAGE__", package)

main_activity.write_text(kotlin)

manifest_path = android / "app/src/main/AndroidManifest.xml"
manifest = manifest_path.read_text()
permissions = [
    '  <uses-permission android:name="android.permission.FOREGROUND_SERVICE" />',
    '  <uses-permission android:name="android.permission.FOREGROUND_SERVICE_MEDIA_PROJECTION" />',
]
for permission in permissions:
    if permission not in manifest:
        manifest = manifest.replace("</manifest>", permission + "\n</manifest>", 1)
service = '''    <service
            android:name=".SnoteScreenCaptureService"
            android:exported="false"
            android:foregroundServiceType="mediaProjection" />
'''
if "SnoteScreenCaptureService" not in manifest:
    manifest = manifest.replace("</application>", service + "    </application>", 1)
manifest_path.write_text(manifest)

gradle_path = android / "app/build.gradle.kts"
gradle = gradle_path.read_text()
rules_path = android / "app/proguard-rules.pro"
rules_path.write_text(
    "-dontwarn com.google.mlkit.vision.text.chinese.**\n"
    "-dontwarn com.google.mlkit.vision.text.devanagari.**\n"
    "-dontwarn com.google.mlkit.vision.text.japanese.**\n"
    "-dontwarn com.google.mlkit.vision.text.korean.**\n"
)
if "proguard-rules.pro" not in gradle:
    lines = gradle.splitlines()
    in_build_types = False
    output = []
    inserted = False
    for line in lines:
        stripped = line.strip()
        if stripped == "buildTypes {":
            in_build_types = True
        elif in_build_types and stripped == "release {":
            output.append(line)
            indent = line[:len(line) - len(line.lstrip())] + "    "
            output.append(indent + "isMinifyEnabled = true")
            output.append(indent + 'proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")')
            inserted = True
            continue
        output.append(line)
    if not inserted:
        raise SystemExit("Could not find release build type to register ProGuard rules")
    gradle = "\n".join(output) + "\n"
    gradle_path.write_text(gradle)

if "SnoteScreenCaptureService" not in manifest_path.read_text():
    raise SystemExit("Android screen capture service declaration missing")
if "captureDisplay" not in main_activity.read_text():
    raise SystemExit("Android screen capture channel handler missing")
print(f"Configured Android MediaProjection capture in {main_activity} (in-memory PNG; no gallery write).")
