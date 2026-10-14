package com.snote.snote_screen_capture;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.Service;
import android.content.Context;
import android.content.Intent;
import android.content.pm.ServiceInfo;
import android.graphics.Bitmap;
import android.graphics.PixelFormat;
import android.hardware.display.DisplayManager;
import android.hardware.display.VirtualDisplay;
import android.media.Image;
import android.media.ImageReader;
import android.media.projection.MediaProjection;
import android.media.projection.MediaProjectionManager;
import android.os.Build;
import android.os.Handler;
import android.os.HandlerThread;
import android.os.IBinder;
import android.util.DisplayMetrics;
import android.view.WindowManager;
import java.io.ByteArrayOutputStream;
import java.nio.ByteBuffer;
import java.util.concurrent.atomic.AtomicBoolean;

/** Single-consent-session screenshot capture to memory only. */
public final class ScreenCaptureService extends Service {
    static final String EXTRA_RESULT_CODE = "snote.capture.resultCode";
    static final String EXTRA_RESULT_DATA = "snote.capture.resultData";
    private static final String CHANNEL_ID = "snote_screen_capture";
    private static final int NOTIFICATION_ID = 58432;

    private final AtomicBoolean finished = new AtomicBoolean(false);
    private final Handler mainHandler = new Handler(android.os.Looper.getMainLooper());
    private HandlerThread imageThread;
    private Handler imageHandler;
    private MediaProjection projection;
    private MediaProjection.Callback projectionCallback;
    private VirtualDisplay virtualDisplay;
    private ImageReader imageReader;
    private Runnable timeout;

    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        startCaptureForeground();
        timeout = () -> finishCapture(null, "Timed out waiting for a screen frame. Please try again.");
        mainHandler.postDelayed(timeout, 10000);
        if (intent == null) {
            finishCapture(null, "The screen capture request was empty.");
            return START_NOT_STICKY;
        }
        try {
            int resultCode = intent.getIntExtra(EXTRA_RESULT_CODE, 0);
            Intent resultData;
            if (Build.VERSION.SDK_INT >= 33) {
                resultData = intent.getParcelableExtra(EXTRA_RESULT_DATA, Intent.class);
            } else {
                //noinspection deprecation
                resultData = intent.getParcelableExtra(EXTRA_RESULT_DATA);
            }
            if (resultCode != -1 || resultData == null) {
                finishCapture(null, "Screen capture permission was not granted.");
                return START_NOT_STICKY;
            }

            MediaProjectionManager manager = (MediaProjectionManager)
                    getSystemService(Context.MEDIA_PROJECTION_SERVICE);
            projection = manager.getMediaProjection(resultCode, resultData);
            if (projection == null) throw new IllegalStateException("Android did not create a capture session.");
            projectionCallback = new MediaProjection.Callback() {
                @Override public void onStop() {
                    if (!finished.get()) finishCapture(null, "Android ended the screen capture session.");
                }
            };
            projection.registerCallback(projectionCallback, mainHandler);

            DisplayMetrics metrics = new DisplayMetrics();
            WindowManager windowManager = (WindowManager) getSystemService(Context.WINDOW_SERVICE);
            if (windowManager == null) throw new IllegalStateException("Display metrics are unavailable.");
            //noinspection deprecation
            windowManager.getDefaultDisplay().getRealMetrics(metrics);
            int width = metrics.widthPixels;
            int height = metrics.heightPixels;
            if (width < 1 || height < 1) throw new IllegalStateException("Invalid display dimensions.");

            imageReader = ImageReader.newInstance(width, height, PixelFormat.RGBA_8888, 2);
            imageThread = new HandlerThread("snote-screen-capture");
            imageThread.start();
            imageHandler = new Handler(imageThread.getLooper());
            imageReader.setOnImageAvailableListener(this::onImageAvailable, imageHandler);
            virtualDisplay = projection.createVirtualDisplay(
                    "SnoteScreenCapture", width, height, metrics.densityDpi,
                    DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR,
                    imageReader.getSurface(), null, imageHandler);
            if (virtualDisplay == null) throw new IllegalStateException("Could not create virtual display.");
        } catch (Exception e) {
            finishCapture(null, "Could not capture the display: " + e.getMessage());
        }
        return START_NOT_STICKY;
    }

    private void startCaptureForeground() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            NotificationManager manager = (NotificationManager) getSystemService(Context.NOTIFICATION_SERVICE);
            if (manager != null) manager.createNotificationChannel(new NotificationChannel(
                    CHANNEL_ID, "Snote screen capture", NotificationManager.IMPORTANCE_LOW));
        }
        Notification.Builder builder = Build.VERSION.SDK_INT >= Build.VERSION_CODES.O
                ? new Notification.Builder(this, CHANNEL_ID)
                : new Notification.Builder(this);
        Notification notification = builder
                .setSmallIcon(android.R.drawable.ic_menu_camera)
                .setContentTitle("Snote screen capture")
                .setContentText("Capturing a screen image for your note")
                .setOngoing(true)
                .build();
        if (Build.VERSION.SDK_INT >= 29) {
            startForeground(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION);
        } else {
            startForeground(NOTIFICATION_ID, notification);
        }
    }

    private void onImageAvailable(ImageReader reader) {
        if (finished.get()) return;
        Image image = null;
        byte[] png = null;
        String failure = null;
        try {
            image = reader.acquireLatestImage();
            if (image == null) return;
            int width = image.getWidth();
            int height = image.getHeight();
            Image.Plane plane = image.getPlanes()[0];
            ByteBuffer buffer = plane.getBuffer();
            int pixelStride = plane.getPixelStride();
            int paddingPixels = Math.max(0, (plane.getRowStride() - pixelStride * width) / pixelStride);
            Bitmap padded = Bitmap.createBitmap(width + paddingPixels, height, Bitmap.Config.ARGB_8888);
            buffer.rewind();
            padded.copyPixelsFromBuffer(buffer);
            Bitmap crop = Bitmap.createBitmap(padded, 0, 0, width, height);
            ByteArrayOutputStream output = new ByteArrayOutputStream();
            if (!crop.compress(Bitmap.CompressFormat.PNG, 100, output)) {
                throw new IllegalStateException("Could not encode PNG.");
            }
            png = output.toByteArray();
            output.close();
            if (crop != padded) crop.recycle();
            padded.recycle();
        } catch (Exception e) {
            failure = "Could not convert screen frame to an image: " + e.getMessage();
        } finally {
            if (image != null) image.close();
        }
        if (png != null && png.length > 0) finishCapture(png, null);
        else if (failure != null) finishCapture(null, failure);
    }

    private void finishCapture(byte[] png, String error) {
        if (!finished.compareAndSet(false, true)) return;
        if (timeout != null) mainHandler.removeCallbacks(timeout);
        SnoteScreenCapturePlugin.complete(png, error);
        releaseCaptureResources();
        if (Build.VERSION.SDK_INT >= 24) stopForeground(STOP_FOREGROUND_REMOVE);
        else {
            //noinspection deprecation
            stopForeground(true);
        }
        stopSelf();
    }

    private void releaseCaptureResources() {
        if (virtualDisplay != null) {
            virtualDisplay.release();
            virtualDisplay = null;
        }
        if (imageReader != null) {
            imageReader.setOnImageAvailableListener(null, null);
            imageReader.close();
            imageReader = null;
        }
        if (projection != null) {
            try {
                if (projectionCallback != null) projection.unregisterCallback(projectionCallback);
                projection.stop();
            } catch (Exception ignored) { /* Android may already have stopped the session. */ }
            projection = null;
            projectionCallback = null;
        }
        if (imageThread != null) {
            imageThread.quitSafely();
            imageThread = null;
            imageHandler = null;
        }
    }

    @Override public void onDestroy() {
        if (!finished.get()) finishCapture(null, "Screen capture service stopped before capture completed.");
        super.onDestroy();
    }

    @Override public IBinder onBind(Intent intent) { return null; }
}
