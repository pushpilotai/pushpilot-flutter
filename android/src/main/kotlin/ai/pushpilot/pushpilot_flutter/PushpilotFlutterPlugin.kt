package ai.pushpilot.pushpilot_flutter

import ai.pushpilot.sdk.PushPilot
import android.content.Context
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/** Passes each Dart call straight to the native PushPilot SDK, which does all the work. */
class PushpilotFlutterPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private lateinit var channel: MethodChannel
    private lateinit var context: Context

    /** Listens on the channel the Dart side calls. */
    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, "ai.pushpilot/sdk")
        channel.setMethodCallHandler(this)
    }

    /** Stops listening when the engine goes away. */
    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }

    /** Runs one SDK call; the SDK returns at once and never throws. */
    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "init" -> PushPilot.init(context, call.argument<String>("sdkKey")!!, call.argument<String>("baseUrl"))
            "setPushToken" -> PushPilot.setPushToken(call.arguments as String?)
            "setExternalUserId" -> PushPilot.setExternalUserId(call.arguments as String?)
            "setAttributes" -> @Suppress("UNCHECKED_CAST") PushPilot.setAttributes(call.arguments as Map<String, Any?>)
            "setTopics" -> @Suppress("UNCHECKED_CAST") PushPilot.setTopics(call.arguments as List<String>)
            "logout" -> PushPilot.logout()
            "forget" -> PushPilot.forget()
            else -> return result.notImplemented()
        }
        result.success(null)
    }
}
