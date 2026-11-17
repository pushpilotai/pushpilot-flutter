package ai.pushpilot.pushpilot_flutter

import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.junit.Assert.assertEquals
import org.junit.Test

/** handleLiveActivityURL on Android: the SDK opens live activity links itself, so the URL comes back as given. */
class LiveActivityUrlTest {
    /** Any URL, even one carrying iOS's live activity marker, is returned unchanged. */
    @Test
    fun returnsTheUrlUnchanged() {
        val url = "https://example.com/orders/42?pushpilot_live=abc"
        var answer: Any? = "nothing"
        PushpilotFlutterPlugin().onMethodCall(MethodCall("handleLiveActivityURL", url), object : MethodChannel.Result {
            /** Keeps the plugin's answer. */
            override fun success(result: Any?) { answer = result }
            /** Fails the test: the call never errors. */
            override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) = throw AssertionError(errorCode)
            /** Fails the test: the call is implemented. */
            override fun notImplemented() = throw AssertionError("not implemented")
        })
        assertEquals(url, answer)
    }
}
