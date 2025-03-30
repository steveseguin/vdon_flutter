package com.cloudwebrtc.vdon_flutter

import android.app.ActivityManager
import android.content.Context
import android.media.MediaCodecList
import android.media.MediaFormat
import android.os.Build
import android.util.Log
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    private val CHANNEL = "vdoninja/device_info"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getDeviceInfo" -> {
                    val deviceInfo = getDeviceInfo()
                    result.success(deviceInfo)
                }
                "getHardwareAcceleration" -> {
                    val hwAccelInfo = getHardwareAcceleration()
                    result.success(hwAccelInfo)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }
    
    private fun getDeviceInfo(): Map<String, Any> {
        val deviceInfo = HashMap<String, Any>()
        
        try {
            // Get total RAM in MB
            val activityManager = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
            val memoryInfo = ActivityManager.MemoryInfo()
            activityManager.getMemoryInfo(memoryInfo)
            val totalMemory = memoryInfo.totalMem / (1024 * 1024) // Convert bytes to MB
            deviceInfo["ramMB"] = totalMemory
            
            // CPU cores
            deviceInfo["cpuCores"] = Runtime.getRuntime().availableProcessors()
            
            // Add other useful device info
            deviceInfo["isLowRamDevice"] = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.KITKAT) {
                activityManager.isLowRamDevice
            } else {
                totalMemory < 2048 // Assume low RAM if < 2GB on older Android versions
            }
            
            // Add Android version
            deviceInfo["androidVersion"] = Build.VERSION.SDK_INT
            deviceInfo["manufacturer"] = Build.MANUFACTURER
            deviceInfo["model"] = Build.MODEL
        } catch (e: Exception) {
            Log.e("VDONinja", "Error getting device info", e)
            deviceInfo["error"] = e.message ?: "Unknown error"
        }
        
        return deviceInfo
    }
    
    private fun getHardwareAcceleration(): Map<String, Any> {
        val result = HashMap<String, Any>()
        
        try {
            // Check for OpenGL ES version
            val activityManager = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
            val configInfo = activityManager.deviceConfigurationInfo
            val supportsEs2 = configInfo.reqGlEsVersion >= 0x20000
            
            // Check if hardware acceleration is enabled in the app
            val hwAccelerated = window.attributes.flags and WindowManager.LayoutParams.FLAG_HARDWARE_ACCELERATED != 0
            
            // Check for video hardware acceleration (MediaCodec)
            var hasVideoHardwareAcceleration = false
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                    val codecList = MediaCodecList(MediaCodecList.REGULAR_CODECS)
                    val videoEncoder = codecList.findEncoderForFormat(
                        MediaFormat.createVideoFormat(MediaFormat.MIMETYPE_VIDEO_AVC, 1280, 720)
                    )
                    hasVideoHardwareAcceleration = videoEncoder != null
                } else {
                    // Default to true for older Android versions
                    hasVideoHardwareAcceleration = true
                }
            } catch (e: Exception) {
                Log.e("VDONinja", "Error checking video hardware acceleration", e)
            }
            
            result["available"] = supportsEs2 && hwAccelerated && hasVideoHardwareAcceleration
            result["openGlEsVersion"] = configInfo.glEsVersion
            result["hwAcceleratedWindow"] = hwAccelerated
            result["videoHwAcceleration"] = hasVideoHardwareAcceleration
            
        } catch (e: Exception) {
            Log.e("VDONinja", "Error checking hardware acceleration", e)
            result["available"] = false
            result["error"] = e.message ?: "Unknown error"
        }
        
        return result
    }
}