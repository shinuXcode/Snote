package com.snote.snote_screen_capture;

import android.app.Activity;
import android.content.Context;
import android.content.Intent;
import android.media.projection.MediaProjectionManager;
import android.os.Build;
import android.os.Handler;
import android.os.Looper;
import androidx.annotation.NonNull;
import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.embedding.engine.plugins.activity.ActivityAware;
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.common.PluginRegistry.ActivityResultListener;

/** Explicit one-shot MediaProjection bridge. */
public final class SnoteScreenCapturePlugin implements FlutterPlugin, MethodChannel.MethodCallHandler,
        ActivityAware, ActivityResultListener {
    private static final int REQUEST_CODE = 58431;
    private static final Object LOCK = new Object();
    private static volatile MethodChannel.Result pending;
    private static final Handler MAIN = new Handler(Looper.getMainLooper());
    private MethodChannel channel;
    private ActivityPluginBinding binding;
    private Activity activity;

    @Override
    public void onAttachedToEngine(@NonNull FlutterPluginBinding engine) {
        channel = new MethodChannel(engine.getBinaryMessenger(), "com.snote/screen_capture");
        channel.setMethodCallHandler(this);
    }

    @Override
    public void onMethodCall(@NonNull MethodCall call, @NonNull MethodChannel.Result result) {
        if (!"captureScreen".equals(call.method)) {
            result.notImplemented();
            return;
        }
        if (activity == null) {
            result.error("NO_ACTIVITY", "Screen capture needs an active Snote window.", null);
            return;
        }
        synchronized (LOCK) {
            if (pending != null) {
                result.error("CAPTURE_BUSY", "A screen capture is already running.", null);
                return;
            }
            pending = result;
        }
        try {
            MediaProjectionManager manager = (MediaProjectionManager)
                    activity.getSystemService(Context.MEDIA_PROJECTION_SERVICE);
            activity.startActivityForResult(manager.createScreenCaptureIntent(), REQUEST_CODE);
        } catch (Exception e) {
            complete(null, "Could not request screen capture permission: " + e.getMessage());
        }
    }

    @Override
    public boolean onActivityResult(int requestCode, int resultCode, Intent data) {
        if (requestCode != REQUEST_CODE) return false;
        if (resultCode != Activity.RESULT_OK || data == null) {
            complete(null, null);
            return true;
        }
        Intent service = new Intent(activity, ScreenCaptureService.class);
        service.putExtra(ScreenCaptureService.EXTRA_RESULT_CODE, resultCode);
        service.putExtra(ScreenCaptureService.EXTRA_RESULT_DATA, data);
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) activity.startForegroundService(service);
            else activity.startService(service);
        } catch (Exception e) {
            complete(null, "Could not start screen capture: " + e.getMessage());
        }
        return true;
    }

    static void complete(byte[] bytes, String error) {
        final MethodChannel.Result result;
        synchronized (LOCK) {
            result = pending;
            pending = null;
        }
        if (result == null) return;
        MAIN.post(() -> {
            if (bytes != null && bytes.length > 0) result.success(bytes);
            else if (error == null) result.success(null);
            else result.error("SCREEN_CAPTURE_FAILED", error, null);
        });
    }

    @Override public void onAttachedToActivity(@NonNull ActivityPluginBinding b) { attach(b); }
    @Override public void onReattachedToActivityForConfigChanges(@NonNull ActivityPluginBinding b) { attach(b); }
    private void attach(ActivityPluginBinding b) {
        binding = b;
        activity = b.getActivity();
        b.addActivityResultListener(this);
    }
    @Override public void onDetachedFromActivityForConfigChanges() { detach(); }
    @Override public void onDetachedFromActivity() { detach(); }
    private void detach() {
        if (binding != null) binding.removeActivityResultListener(this);
        binding = null;
        activity = null;
    }
    @Override
    public void onDetachedFromEngine(@NonNull FlutterPluginBinding engine) {
        if (channel != null) channel.setMethodCallHandler(null);
        detach();
        channel = null;
    }
}
