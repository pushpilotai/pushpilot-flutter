package ai.pushpilot.pushpilot_flutter

import ai.pushpilot.sdk.PushPilot
import android.content.ActivityNotFoundException
import android.content.BroadcastReceiver
import android.content.ContentProvider
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.database.Cursor
import android.net.Uri
import io.flutter.plugin.common.MethodChannel

/** Receives every FCM message for the app and hands PushPilot's own to the native SDK, which shows them. */
class PushPilotMessageReceiver : BroadcastReceiver() {
    /** Ignores other pushes; for ours, keeps the broadcast alive while the SDK downloads the image and posts it. */
    override fun onReceive(context: Context, intent: Intent) {
        val extras = intent.extras ?: return
        @Suppress("DEPRECATION")
        val data = extras.keySet().mapNotNull { key -> (extras.get(key) as? String)?.let { key to it } }.toMap()
        // The SDK's own rule for "ours"; checked here so other pushes cost no thread.
        if (data["source"] != "pushpilot") return
        val pending = goAsync()
        Thread {
            try {
                PushPilot.handleMessage(context.applicationContext, data)
            } finally {
                pending.finish()
            }
        }.start()
    }
}

/**
 * Runs when the app process starts, before the tap activity of a push that launches a killed app, so the
 * native link handler is already set for that tap. The SDK starts itself from the key it saved at init.
 */
class PushPilotStartupProvider : ContentProvider() {
    /** Sets the native link handler if Dart routed links in the app's last run. */
    override fun onCreate(): Boolean {
        context?.let { Bridge.start(it) }
        return true
    }

    // A provider must implement these; this one stores nothing.
    override fun query(uri: Uri, projection: Array<String>?, selection: String?, selectionArgs: Array<String>?, sortOrder: String?): Cursor? = null
    override fun getType(uri: Uri): String? = null
    override fun insert(uri: Uri, values: ContentValues?): Uri? = null
    override fun delete(uri: Uri, selection: String?, selectionArgs: Array<String>?): Int = 0
    override fun update(uri: Uri, values: ContentValues?, selection: String?, selectionArgs: Array<String>?): Int = 0
}

/** Process-wide routing of taps and links to Dart; they can arrive before any Flutter engine exists. */
internal object Bridge {
    private const val PREFS = "ai.pushpilot.flutter"
    private const val DART_HANDLES_LINKS = "dartHandlesLinks"

    val gate = DartGate()
    /** The channel of the engine whose Dart called init. */
    var channel: MethodChannel? = null
    var dartHandlesLinks = false
        private set
    var dartHandlesTaps = false
    private lateinit var context: Context

    /** The native link handler: each link waits for Dart's init, then goes to Dart or to Android. */
    val linkHandler = PushPilot.LinkHandler { link -> gate.run { open(link) } }

    /** Keeps the app context; sets the native handler when Dart had one last time. */
    fun start(context: Context) {
        this.context = context.applicationContext
        if (prefs().getBoolean(DART_HANDLES_LINKS, false)) PushPilot.setLinkHandler(linkHandler)
    }

    /** Applies Dart's choice now and remembers it for the next process start. */
    fun routeLinksToDart(value: Boolean) {
        dartHandlesLinks = value
        prefs().edit().putBoolean(DART_HANDLES_LINKS, value).apply()
        PushPilot.setLinkHandler(if (value) linkHandler else null)
    }

    /** Gives a link to Dart, or opens it the way the SDK would when Dart has no handler. */
    private fun open(link: Uri) {
        val dart = channel
        if (dartHandlesLinks && dart != null) return dart.invokeMethod("onLink", link.toString())
        try {
            context.startActivity(Intent(Intent.ACTION_VIEW, link).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        } catch (e: ActivityNotFoundException) {
            // The SDK already opened the app for this tap, which is its fallback too.
        }
    }

    /** Passes the PushPilot tap that started [intent] to Dart, once per notification. */
    fun tapped(intent: Intent?) {
        // A relaunch from Recents repeats the old intent; that is not a new tap.
        if (intent == null || intent.flags and Intent.FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY != 0) return
        val tap = PushPilot.tappedNotification(intent) ?: return
        if (!gate.firstTap(tap.notificationId)) return
        gate.run {
            if (dartHandlesTaps) channel?.invokeMethod("onTap", mapOf("notificationId" to tap.notificationId, "data" to tap.data))
        }
    }

    private fun prefs() = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
}

/** Holds work for Dart until Dart has called init, and remembers which taps were already passed on. */
internal class DartGate {
    private var started = false
    private val waiting = mutableListOf<() -> Unit>()
    private val seen = mutableSetOf<String>()

    /** Runs [work] now, or once Dart starts. */
    fun run(work: () -> Unit) {
        if (started) work() else waiting += work
    }

    /** Marks Dart as started and runs what waited, in arrival order. */
    fun start() {
        started = true
        val ready = waiting.toList()
        waiting.clear()
        ready.forEach { it() }
    }

    /** Holds work again, until the next init, once the engine that started is gone. */
    fun stop() {
        started = false
    }

    /** True the first time [notificationId] is seen in this process. */
    fun firstTap(notificationId: String) = seen.add(notificationId)
}
