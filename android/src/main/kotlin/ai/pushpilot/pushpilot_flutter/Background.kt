package ai.pushpilot.pushpilot_flutter

import ai.pushpilot.sdk.PushPilot
import android.content.BroadcastReceiver
import android.content.ContentProvider
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.database.Cursor
import android.net.Uri

/** The last `init` arguments from Dart, kept so the SDK can start in processes where no Dart code runs. */
internal object StoredConfig {
    private const val PREFS = "ai.pushpilot.flutter"

    /** Remembers the SDK key and base URL for later process starts. */
    fun save(context: Context, sdkKey: String, baseUrl: String?) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
            .putString("sdkKey", sdkKey).putString("baseUrl", baseUrl).apply()
    }

    /** Starts the SDK with the remembered values; does nothing before Dart's first `init`. */
    fun startSdk(context: Context) {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val sdkKey = prefs.getString("sdkKey", null) ?: return
        PushPilot.init(context, sdkKey, prefs.getString("baseUrl", null))
    }
}

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

/** Runs before any receiver or activity of the app, so delivery and tap events are recorded with Dart not running. */
class PushPilotInitProvider : ContentProvider() {
    /** Starts the SDK from the stored config. */
    override fun onCreate(): Boolean {
        context?.let { StoredConfig.startSdk(it) }
        return true
    }

    // A provider must implement these; this one stores nothing.
    override fun query(uri: Uri, projection: Array<String>?, selection: String?, selectionArgs: Array<String>?, sortOrder: String?): Cursor? = null
    override fun getType(uri: Uri): String? = null
    override fun insert(uri: Uri, values: ContentValues?): Uri? = null
    override fun delete(uri: Uri, selection: String?, selectionArgs: Array<String>?): Int = 0
    override fun update(uri: Uri, values: ContentValues?, selection: String?, selectionArgs: Array<String>?): Int = 0
}
