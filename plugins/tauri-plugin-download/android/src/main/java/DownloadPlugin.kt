package ph.intportal.download

import android.app.Activity
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.os.StatFs
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import app.tauri.annotation.Command
import app.tauri.annotation.InvokeArg
import app.tauri.annotation.TauriPlugin
import app.tauri.plugin.Invoke
import app.tauri.plugin.JSObject
import app.tauri.plugin.Plugin

@InvokeArg
class PathArgs {
    var path: String = ""
}

@InvokeArg
class KeepArgs {
    var pct: Int = 0
    var text: String = ""
}

/**
 * The model download is the app's own Rust code; this only keeps the process alive while it runs
 * (spec 021 C5), with a progress notification, and reads free storage.
 */
@TauriPlugin
class DownloadPlugin(private val activity: Activity) : Plugin(activity) {
    @Command
    fun space(invoke: Invoke) {
        val args = invoke.parseArgs(PathArgs::class.java)
        invoke.resolve(JSObject().put("bytes", StatFs(args.path).availableBytes))
    }

    @Command
    fun keepAlive(invoke: Invoke) {
        val args = invoke.parseArgs(KeepArgs::class.java)
        KeepAlive.show(activity.applicationContext, args.pct, args.text)
        invoke.resolve()
    }

    @Command
    fun release(invoke: Invoke) {
        val ctx = activity.applicationContext
        ctx.stopService(Intent(ctx, KeepAlive::class.java))
        invoke.resolve()
    }
}

class KeepAlive : Service() {
    companion object {
        private const val ID = 4207
        private const val CHANNEL = "intassis-download"

        @Volatile
        private var running = false

        private fun notification(ctx: Context, pct: Int, text: String): Notification {
            val nm = ctx.getSystemService(NotificationManager::class.java)
            if (Build.VERSION.SDK_INT >= 26 && nm.getNotificationChannel(CHANNEL) == null) {
                nm.createNotificationChannel(NotificationChannel(CHANNEL, "Adding IntAssis", NotificationManager.IMPORTANCE_LOW))
            }
            val open = ctx.packageManager.getLaunchIntentForPackage(ctx.packageName)?.let {
                PendingIntent.getActivity(ctx, 0, it, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
            }
            return NotificationCompat.Builder(ctx, CHANNEL)
                .setSmallIcon(android.R.drawable.stat_sys_download)
                .setContentTitle("Adding IntAssis")
                .setContentText(text)
                .setProgress(100, pct, pct <= 0)
                .setOngoing(true)
                .setOnlyAlertOnce(true)
                .setContentIntent(open)
                .build()
        }

        fun show(ctx: Context, pct: Int, text: String) {
            if (running) {
                ctx.getSystemService(NotificationManager::class.java).notify(ID, notification(ctx, pct, text))
                return
            }
            try {
                ContextCompat.startForegroundService(ctx, Intent(ctx, KeepAlive::class.java).putExtra("pct", pct).putExtra("text", text))
            } catch (e: Exception) {
                // Android 12+ refuses a foreground service started from the background. The download
                // still runs while the system lets the app live; the next start from the app retries.
            }
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val n = notification(this, intent?.getIntExtra("pct", 0) ?: 0, intent?.getStringExtra("text") ?: "")
        if (Build.VERSION.SDK_INT >= 29) startForeground(ID, n, ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC) else startForeground(ID, n)
        running = true
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        running = false
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null
}
