package com.cloudwebrtc.vdon_flutter

import android.os.Bundle
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    companion object {
        private const val TAG = "VDONinja"

        init {
            Log.d(TAG, "MainActivity class loaded!")
        }
    }

    init {
        Log.d(TAG, "MainActivity instance created!")
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        Log.d(TAG, "MainActivity.onCreate called!")
        super.onCreate(savedInstanceState)

        // Try to register plugin in onCreate as workaround
        flutterEngine?.let { engine ->
            Log.d(TAG, "FlutterEngine available in onCreate, registering plugin...")
            val plugin = VDONinjaPlugin()
            engine.plugins.add(plugin)
            Log.d(TAG, "VDONinjaPlugin registered in onCreate!")
        } ?: Log.w(TAG, "FlutterEngine not available in onCreate")
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        Log.d(TAG, "MainActivity.configureFlutterEngine called!")
        super.configureFlutterEngine(flutterEngine)

        val plugin = VDONinjaPlugin()
        flutterEngine.plugins.add(plugin)
        Log.d(TAG, "VDONinjaPlugin registered in configureFlutterEngine!")
    }
}