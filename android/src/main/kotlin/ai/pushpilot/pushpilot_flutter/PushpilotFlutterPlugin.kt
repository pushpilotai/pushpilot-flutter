package ai.pushpilot.pushpilot_flutter

import ai.pushpilot.sdk.PushPilot
import android.content.Context
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout
import io.flutter.embedding.android.FlutterView
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry
import kotlin.math.roundToInt

/** Passes each Dart call straight to the native PushPilot SDK, and taps and links from it back to Dart. */
class PushpilotFlutterPlugin : FlutterPlugin, MethodChannel.MethodCallHandler, ActivityAware {
    private lateinit var channel: MethodChannel
    private lateinit var context: Context
    private var activity: ActivityPluginBinding? = null
    private val newIntents = PluginRegistry.NewIntentListener { intent -> Bridge.tapped(intent); false }
    /** Stand-ins for Dart's PushPilotMark widgets by name: transparent views the SDK can point coach marks at. */
    private val marks = HashMap<String, View>()

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
                // Dart's init runs after the activity resumed, which the SDK's lifecycle watcher missed.
                activity?.activity?.let(PushPilot::setCurrentActivity)
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
            // The SDK opens live activity links itself on Android (the App Group in "init" is iOS only).
            "handleLiveActivityURL" -> return result.success(call.arguments as String)
            // Channel calls arrive on the main thread, which the SDK requires.
            "showInApp" -> return result.success(PushPilot.showInApp(call.arguments as String))
            "markView" -> mark(call)
            "unmarkView" -> marks.remove(call.arguments as String)?.let { view ->
                PushPilot.unmarkView(call.arguments as String)
                (view.parent as? ViewGroup)?.removeView(view)
            }
            else -> return result.notImplemented()
        }
        result.success(null)
    }

    /**
     * Places the stand-in view for a PushPilotMark at its rect (logical pixels from the FlutterView's top left)
     * and names it for the SDK. It draws nothing and takes no touches, so the Flutter UI under it works as before.
     */
    private fun mark(call: MethodCall) {
        val host = activity?.activity?.window?.decorView?.let(::findFlutterView) ?: return
        val name = call.argument<String>("name")!!
        val density = host.resources.displayMetrics.density
        fun px(key: String) = (call.argument<Double>(key)!! * density).roundToInt()
        val view = marks.getOrPut(name) {
            View(host.context).apply { importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO }
        }
        // Left, not start: Flutter's x is from the left in right-to-left layouts too.
        val size = FrameLayout.LayoutParams(px("width"), px("height"), Gravity.TOP or Gravity.LEFT)
        // A new activity after a configuration change has a new FlutterView.
        if (view.parent !== host) {
            (view.parent as? ViewGroup)?.removeView(view)
            host.addView(view, size)
        } else if (view.layoutParams.width != size.width || view.layoutParams.height != size.height) {
            view.layoutParams = size
        }
        // Moving by translation needs no layout pass, which keeps scrolling cheap.
        view.translationX = px("x").toFloat()
        view.translationY = px("y").toFloat()
        PushPilot.markView(view, name)
    }

    /** The first FlutterView in [view]'s tree: the one an app built on FlutterActivity shows. */
    private fun findFlutterView(view: View): FlutterView? = when (view) {
        is FlutterView -> view
        is ViewGroup -> (0 until view.childCount).firstNotNullOfOrNull { findFlutterView(view.getChildAt(it)) }
        else -> null
    }
}
