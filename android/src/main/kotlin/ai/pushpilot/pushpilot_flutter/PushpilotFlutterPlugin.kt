package ai.pushpilot.pushpilot_flutter

import ai.pushpilot.sdk.PushPilot
import android.content.Context
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry

/** Passes each Dart call straight to the native PushPilot SDK, and taps and links from it back to Dart. */
class PushpilotFlutterPlugin : FlutterPlugin, MethodChannel.MethodCallHandler, ActivityAware {
    private lateinit var channel: MethodChannel
    private lateinit var context: Context
    private var activity: ActivityPluginBinding? = null
    private val newIntents = PluginRegistry.NewIntentListener { intent -> Bridge.tapped(intent); false }

    /** Listens on the channel the Dart side calls. */
    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        Bridge.start(context)
        channel = MethodChannel(binding.binaryMessenger, "ai.pushpilot/sdk")
        channel.setMethodCallHandler(this)
    }

    /** Stops listening; taps and links wait for the next init if this was the engine that started. */
    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        if (Bridge.channel === channel) {
            Bridge.channel = null
            Bridge.gate.stop()
        }
    }

    /** Reads the tap that opened the activity, and later ones that reach it as new intents. */
    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding
        binding.addOnNewIntentListener(newIntents)
        Bridge.tapped(binding.activity.intent)
    }

    /** Same as a first attach; a tap already passed on is not passed again. */
    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) = onAttachedToActivity(binding)

    /** Stops listening for new intents. */
    override fun onDetachedFromActivity() {
        activity?.removeOnNewIntentListener(newIntents)
        activity = null
    }

    /** Same as a final detach. */
    override fun onDetachedFromActivityForConfigChanges() = onDetachedFromActivity()

    /** Runs one SDK call; the SDK returns at once and never throws. */
    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "init" -> {
                PushPilot.init(context, call.argument<String>("sdkKey")!!, call.argument<String>("baseUrl"))
                // This engine's Dart is now ready for the taps and links that waited.
                Bridge.channel = channel
                Bridge.gate.start()
            }
            "setPushToken" -> PushPilot.setPushToken(call.arguments as String?)
            "setExternalUserId" -> PushPilot.setExternalUserId(call.arguments as String?)
            "setAttributes" -> @Suppress("UNCHECKED_CAST") PushPilot.setAttributes(call.arguments as Map<String, Any?>)
            "setTopics" -> @Suppress("UNCHECKED_CAST") PushPilot.setTopics(call.arguments as List<String>)
            "logout" -> PushPilot.logout()
            "forget" -> PushPilot.forget()
            "setLinkHandler" -> Bridge.routeLinksToDart(call.arguments as Boolean)
            "setTapHandler" -> Bridge.dartHandlesTaps = call.arguments as Boolean
            else -> return result.notImplemented()
        }
        result.success(null)
    }
}
