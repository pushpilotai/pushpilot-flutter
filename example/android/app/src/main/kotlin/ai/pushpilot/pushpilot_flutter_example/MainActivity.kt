package ai.pushpilot.pushpilot_flutter_example

import android.Manifest
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/** The example's activity; it also asks for notification permission, which PushPilot never does. */
class MainActivity : FlutterActivity() {
    /** Answers the Dart side's "request" with the Android 13+ notification permission prompt. */
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "pushpilot_example/permission").setMethodCallHandler { _, result ->
            if (Build.VERSION.SDK_INT >= 33) requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 0)
            result.success(null)
        }
    }
}
