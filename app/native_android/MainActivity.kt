package com.snote.snote

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.media.projection.MediaProjectionManager
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val captureRequestCode = 49201

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.snote/screen_capture")
            .setMethodCallHandler { call, result ->
                if (call.method != "captureDisplay") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                if (!ScreenCaptureBridge.attach(result)) {
                    result.error("capture_in_progress", "A screen capture is already running.", null)
                    return@setMethodCallHandler
                }
                try {
                    val manager = getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
                    startActivityForResult(manager.createScreenCaptureIntent(), captureRequestCode)
                } catch (error: Exception) {
                    ScreenCaptureBridge.complete(null, error.message ?: "Could not start screen capture consent.")
                }
            }
    }

    @Deprecated("Deprecated Android Activity result API, retained for Flutter host compatibility")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != captureRequestCode) return
        if (resultCode != Activity.RESULT_OK || data == null) {
            ScreenCaptureBridge.complete(null, null)
            return
        }
        try {
            val serviceIntent = Intent(this, ScreenCaptureService::class.java).apply {
                putExtra(ScreenCaptureService.EXTRA_RESULT_CODE, resultCode)
                putExtra(ScreenCaptureService.EXTRA_RESULT_DATA, data)
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) startForegroundService(serviceIntent)
            else startService(serviceIntent)
        } catch (error: Exception) {
            ScreenCaptureBridge.complete(null, error.message ?: "Could not start the capture service.")
        }
    }
}
