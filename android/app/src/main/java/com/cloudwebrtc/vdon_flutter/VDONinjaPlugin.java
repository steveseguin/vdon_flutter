package com.cloudwebrtc.vdon_flutter;

import android.app.Activity;
import android.app.ActivityManager;
import android.content.Context;
import android.media.MediaCodecList;
import android.media.MediaFormat;
import android.os.Build;
import android.util.Log;
import android.view.Window;
import android.view.WindowManager;
import androidx.annotation.NonNull;
import androidx.annotation.Nullable;
import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.embedding.engine.plugins.activity.ActivityAware;
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import java.util.HashMap;
import java.util.Map;

public class VDONinjaPlugin implements FlutterPlugin, ActivityAware, MethodChannel.MethodCallHandler {
    private static final String TAG = "VDONinja";
    private static final String DEVICE_CHANNEL = "vdoninja/device_info";
    private static final String MEDIA_CHANNEL = "vdoninja/media_projection";

    private Context applicationContext;
    private Activity activity;
    private MethodChannel deviceChannel;
    private MethodChannel mediaProjectionChannel;

    public VDONinjaPlugin() {
        Log.d(TAG, "VDONinjaPlugin constructor called!");
    }

    @Override
    public void onAttachedToEngine(@NonNull FlutterPluginBinding binding) {
        applicationContext = binding.getApplicationContext();
        deviceChannel = new MethodChannel(binding.getBinaryMessenger(), DEVICE_CHANNEL);
        mediaProjectionChannel = new MethodChannel(binding.getBinaryMessenger(), MEDIA_CHANNEL);
        deviceChannel.setMethodCallHandler(this);
        mediaProjectionChannel.setMethodCallHandler(this);
        Log.d(TAG, "VDONinjaPlugin attached to engine - channels registered!");
    }

    @Override
    public void onDetachedFromEngine(@NonNull FlutterPluginBinding binding) {
        if (deviceChannel != null) {
            deviceChannel.setMethodCallHandler(null);
            deviceChannel = null;
        }
        if (mediaProjectionChannel != null) {
            mediaProjectionChannel.setMethodCallHandler(null);
            mediaProjectionChannel = null;
        }
        applicationContext = null;
        Log.d(TAG, "VDONinjaPlugin detached from engine");
    }

    @Override
    public void onAttachedToActivity(@NonNull ActivityPluginBinding binding) {
        activity = binding.getActivity();
        Log.d(TAG, "Activity attached to VDONinjaPlugin: " + activity.getClass().getSimpleName());
    }

    @Override
    public void onDetachedFromActivityForConfigChanges() {
        Log.d(TAG, "Activity detached for config changes");
        activity = null;
    }

    @Override
    public void onReattachedToActivityForConfigChanges(@NonNull ActivityPluginBinding binding) {
        activity = binding.getActivity();
        Log.d(TAG, "Activity reattached after config changes: " + activity.getClass().getSimpleName());
    }

    @Override
    public void onDetachedFromActivity() {
        Log.d(TAG, "Activity fully detached from VDONinjaPlugin");
        activity = null;
    }

    @Override
    public void onMethodCall(@NonNull MethodCall call, @NonNull MethodChannel.Result result) {
        switch (call.method) {
            case "getDeviceInfo":
                result.success(getDeviceInfo());
                break;
            case "getHardwareAcceleration":
                result.success(getHardwareAcceleration());
                break;
            case "startMediaProjectionService":
                result.success(startMediaProjectionService());
                break;
            case "stopMediaProjectionService":
                result.success(stopMediaProjectionService());
                break;
            case "isMediaProjectionServiceRunning":
                result.success(MediaProjectionService.isRunning());
                break;
            default:
                result.notImplemented();
                break;
        }
    }

    private Map<String, Object> getDeviceInfo() {
        Map<String, Object> deviceInfo = new HashMap<>();
        Context context = getActiveContext();
        if (context == null) {
            deviceInfo.put("error", "Context unavailable");
            return deviceInfo;
        }

        try {
            ActivityManager activityManager = (ActivityManager) context.getSystemService(Context.ACTIVITY_SERVICE);
            if (activityManager != null) {
                ActivityManager.MemoryInfo memoryInfo = new ActivityManager.MemoryInfo();
                activityManager.getMemoryInfo(memoryInfo);
                long totalMemory = memoryInfo.totalMem / (1024 * 1024);
                deviceInfo.put("ramMB", totalMemory);
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.KITKAT) {
                    deviceInfo.put("isLowRamDevice", activityManager.isLowRamDevice());
                } else {
                    deviceInfo.put("isLowRamDevice", totalMemory < 2048);
                }
            }

            deviceInfo.put("cpuCores", Runtime.getRuntime().availableProcessors());
            deviceInfo.put("androidVersion", Build.VERSION.SDK_INT);
            deviceInfo.put("manufacturer", Build.MANUFACTURER);
            deviceInfo.put("model", Build.MODEL);
        } catch (Exception e) {
            Log.e(TAG, "Error getting device info", e);
            deviceInfo.put("error", e.getMessage() != null ? e.getMessage() : "Unknown error");
        }

        return deviceInfo;
    }

    private Map<String, Object> getHardwareAcceleration() {
        Map<String, Object> result = new HashMap<>();
        Activity currentActivity = activity;
        Context context = getActiveContext();
        if (currentActivity == null || context == null) {
            result.put("available", false);
            result.put("error", "Activity unavailable");
            return result;
        }

        try {
            ActivityManager activityManager = (ActivityManager) context.getSystemService(Context.ACTIVITY_SERVICE);
            android.content.pm.ConfigurationInfo configInfo = activityManager != null ? activityManager.getDeviceConfigurationInfo() : null;
            boolean supportsEs2 = configInfo != null && configInfo.reqGlEsVersion >= 0x20000;

            Window window = currentActivity.getWindow();
            boolean hwAccelerated = false;
            if (window != null) {
                WindowManager.LayoutParams params = window.getAttributes();
                hwAccelerated = (params.flags & WindowManager.LayoutParams.FLAG_HARDWARE_ACCELERATED) != 0;
            }

            boolean hasVideoHardwareAcceleration = false;
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                    MediaCodecList codecList = new MediaCodecList(MediaCodecList.REGULAR_CODECS);
                    String videoEncoder = codecList.findEncoderForFormat(
                        MediaFormat.createVideoFormat(MediaFormat.MIMETYPE_VIDEO_AVC, 1280, 720)
                    );
                    hasVideoHardwareAcceleration = videoEncoder != null;
                } else {
                    hasVideoHardwareAcceleration = true;
                }
            } catch (Exception e) {
                Log.e(TAG, "Error checking video hardware acceleration", e);
            }

            result.put("available", supportsEs2 && hwAccelerated && hasVideoHardwareAcceleration);
            result.put("openGlEsVersion", configInfo != null ? configInfo.getGlEsVersion() : "unknown");
            result.put("hwAcceleratedWindow", hwAccelerated);
            result.put("videoHwAcceleration", hasVideoHardwareAcceleration);
        } catch (Exception e) {
            Log.e(TAG, "Error checking hardware acceleration", e);
            result.put("available", false);
            result.put("error", e.getMessage() != null ? e.getMessage() : "Unknown error");
        }

        return result;
    }

    private Boolean startMediaProjectionService() {
        Context context = getActiveContext();
        if (context == null) {
            Log.e(TAG, "Cannot start MediaProjectionService: context unavailable");
            return false;
        }
        boolean started = MediaProjectionService.startService(context);
        Log.d(TAG, "startMediaProjectionService invoked, result=" + started);
        return started;
    }

    private Boolean stopMediaProjectionService() {
        Context context = getActiveContext();
        if (context == null) {
            Log.e(TAG, "Cannot stop MediaProjectionService: context unavailable");
            return false;
        }
        boolean stopped = MediaProjectionService.stopService(context);
        Log.d(TAG, "stopMediaProjectionService invoked, result=" + stopped);
        return stopped;
    }

    @Nullable
    private Context getActiveContext() {
        if (applicationContext != null) {
            return applicationContext;
        }
        if (activity != null) {
            return activity.getApplicationContext();
        }
        return null;
    }
}
