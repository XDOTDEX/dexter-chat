package com.dexterchat.dexter_chat

import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Channel used by the photo viewer to toggle FLAG_SECURE
        // (blocks screenshots / screen recording while a view-limited
        // photo is on screen).
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "dexter/secure")
            .setMethodCallHandler { call, result ->
                if (call.method == "setSecure") {
                    val secure = call.arguments as? Boolean ?: false
                    runOnUiThread {
                        if (secure) {
                            window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
                        } else {
                            window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                        }
                    }
                    result.success(null)
                } else {
                    result.notImplemented()
                }
            }
    }
}
