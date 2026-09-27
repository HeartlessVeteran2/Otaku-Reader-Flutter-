package com.otakureader.otaku_reader

import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // The reader's secure-screen setting. Orientation and immersive mode
        // are plain `SystemChrome` calls on the Dart side and need nothing
        // here; FLAG_SECURE is the one Android exposes only through
        // WindowManager, with no Flutter wrapper.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "setSecure" -> {
                        val on = call.arguments as? Boolean
                        if (on == null) {
                            // Answered rather than thrown: the Dart side reads
                            // a false as "not applied", which is exactly what
                            // happened, and an error would reach an unawaited
                            // caller as an unhandled async error.
                            result.success(false)
                        } else {
                            result.success(applySecure(on))
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    /**
     * Returns whether the flag was actually changed.
     *
     * The Dart contract is that a false means the platform did not apply it —
     * a secure-screen setting that claims a privacy property it does not have
     * is worse than no setting, so this reports rather than swallows.
     */
    private fun applySecure(on: Boolean): Boolean =
        try {
            if (on) {
                window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
            } else {
                window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
            }
            true
        } catch (e: Exception) {
            false
        }

    private companion object {
        const val CHANNEL = "otaku_reader/screen"
    }
}
