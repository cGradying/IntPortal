package ph.intportal.glance

import android.Manifest
import android.app.Activity
import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.os.SystemClock
import android.text.format.DateFormat
import android.view.View
import android.widget.RemoteViews
import app.tauri.PermissionState
import app.tauri.annotation.Command
import app.tauri.annotation.InvokeArg
import app.tauri.annotation.Permission
import app.tauri.annotation.PermissionCallback
import app.tauri.annotation.TauriPlugin
import app.tauri.plugin.Invoke
import app.tauri.plugin.Plugin
import java.util.Date

@InvokeArg
class NextClass {
    var code: String = ""
    var title: String = ""
    /** Unix milliseconds. */
    var start: Double = 0.0
    var end: Double = 0.0
    var online: Boolean = false
}

@InvokeArg
class UpdateArgs {
    var next: NextClass? = null
    var line: String = ""
}

/**
 * The glance outside the app, Android's way. Phones here have a punch-hole
 * camera, not a Dynamic Island, so the Live Activity becomes a Live Update:
 * a promoted ongoing notification whose countdown rides in the status-bar
 * chip next to the camera (Android 16), or a plain ongoing notification
 * before that. The widget shows the same next class on the home screen.
 */
@TauriPlugin(permissions = [Permission(strings = [Manifest.permission.POST_NOTIFICATIONS], alias = "notifications")])
class GlancePlugin(private val activity: Activity) : Plugin(activity) {
    @Command
    fun update(invoke: Invoke) {
        val args = invoke.parseArgs(UpdateArgs::class.java)
        val n = args.next
        Glance.prefs(activity).edit().apply {
            clear()
            putString("line", args.line)
            if (n != null) {
                putString("code", n.code)
                putString("title", n.title)
                putLong("start", n.start.toLong())
                putLong("end", n.end.toLong())
                putBoolean("online", n.online)
            }
        }.commit()
        // Like iOS asking to allow Live Activities when the first one starts:
        // ask once, when there is a class to count down to.
        val asked = activity.getSharedPreferences("glance-asked", Context.MODE_PRIVATE).getBoolean("asked", false)
        if (Glance.refresh(activity) && Build.VERSION.SDK_INT >= 33 && !asked &&
            getPermissionState("notifications") != PermissionState.GRANTED
        ) {
            activity.getSharedPreferences("glance-asked", Context.MODE_PRIVATE).edit().putBoolean("asked", true).apply()
            requestPermissionForAlias("notifications", invoke, "answered")
        } else {
            invoke.resolve()
        }
    }

    @PermissionCallback
    private fun answered(invoke: Invoke) {
        Glance.refresh(activity)
        invoke.resolve()
    }
}

/** What the app last handed over, and everything drawn from it. */
object Glance {
    private const val CHANNEL = "next-class"
    private const val NOTIFICATION = 1
    private const val HOUR = 3_600_000L

    data class Next(val code: String, val title: String, val start: Long, val end: Long, val online: Boolean)

    fun prefs(context: Context) = context.getSharedPreferences("glance", Context.MODE_PRIVATE)

    private fun read(context: Context): Pair<Next?, String> {
        val p = prefs(context)
        val line = p.getString("line", null) ?: "Open IntPortal to sync"
        val code = p.getString("code", null) ?: return null to line
        return Next(code, p.getString("title", "")!!, p.getLong("start", 0), p.getLong("end", 0), p.getBoolean("online", false)) to line
    }

    /** Redraws the widget and the Live Update for now, then wakes again at
     *  the next turn: an hour before class, its start, its end. True while
     *  the Live Update is wanted. */
    fun refresh(context: Context): Boolean {
        val (n, line) = read(context)
        val now = System.currentTimeMillis()
        val next = n?.takeIf { it.end > now }
        drawWidgets(context, next, if (n != null && next == null) "Open IntPortal for what's next" else line, now)
        val live = next?.takeIf { it.start - now <= HOUR }
        liveUpdate(context, live, now)
        val turn = next?.let { listOf(it.start - HOUR, it.start, it.end).firstOrNull { t -> t > now } }
        val tick = PendingIntent.getBroadcast(
            context, 0, Intent(context, GlanceTick::class.java), PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val alarms = context.getSystemService(AlarmManager::class.java)
        if (turn == null) alarms.cancel(tick) else alarms.set(AlarmManager.RTC, turn, tick)
        return live != null
    }

    private fun launch(context: Context): PendingIntent? =
        context.packageManager.getLaunchIntentForPackage(context.packageName)?.let {
            PendingIntent.getActivity(context, 0, it, PendingIntent.FLAG_IMMUTABLE)
        }

    private fun time(context: Context, ms: Long) = DateFormat.getTimeFormat(context).format(Date(ms))

    private fun drawWidgets(context: Context, n: Next?, line: String, now: Long) {
        val manager = AppWidgetManager.getInstance(context)
        val ids = manager.getAppWidgetIds(ComponentName(context, NextClassWidget::class.java))
        if (ids.isEmpty()) return
        val v = RemoteViews(context.packageName, R.layout.glance_widget)
        v.setOnClickPendingIntent(R.id.glance_root, launch(context))
        val shown = { id: Int, on: Boolean -> v.setViewVisibility(id, if (on) View.VISIBLE else View.GONE) }
        if (n == null) {
            v.setTextViewText(R.id.glance_label, "IntPortal")
            v.setTextViewText(R.id.glance_line, line)
            listOf(R.id.glance_code, R.id.glance_title, R.id.glance_countdown, R.id.glance_until, R.id.glance_online).forEach { shown(it, false) }
            shown(R.id.glance_line, true)
        } else {
            val before = n.start > now
            v.setTextViewText(R.id.glance_label, if (before) "UP NEXT" else "IN CLASS")
            v.setTextViewText(R.id.glance_code, n.code)
            v.setTextViewText(R.id.glance_title, n.title)
            v.setChronometer(R.id.glance_countdown, SystemClock.elapsedRealtime() + (n.start - now), null, before)
            v.setChronometerCountDown(R.id.glance_countdown, true)
            v.setTextViewText(R.id.glance_until, "until ${time(context, n.end)}")
            listOf(R.id.glance_code, R.id.glance_title).forEach { shown(it, true) }
            shown(R.id.glance_countdown, before)
            shown(R.id.glance_until, !before)
            shown(R.id.glance_online, n.online)
            shown(R.id.glance_line, false)
        }
        manager.updateAppWidget(ids, v)
    }

    private fun liveUpdate(context: Context, n: Next?, now: Long) {
        val manager = context.getSystemService(NotificationManager::class.java)
        if (n == null) return manager.cancel(NOTIFICATION)
        if (Build.VERSION.SDK_INT >= 26) {
            manager.createNotificationChannel(NotificationChannel(CHANNEL, "Next class", NotificationManager.IMPORTANCE_DEFAULT).apply {
                description = "A countdown to your next class, from an hour before until it ends."
                setSound(null, null)
                enableVibration(false)
            })
        }
        val before = n.start > now
        @Suppress("DEPRECATION")
        val b = (if (Build.VERSION.SDK_INT >= 26) Notification.Builder(context, CHANNEL) else Notification.Builder(context))
            .setSmallIcon(R.drawable.glance_glyph_mono)
            .setColor(0xFFF5B227.toInt())
            .setContentTitle(n.code)
            .setContentText("${n.title}${if (n.online) " · Online" else ""} · ${time(context, n.start)}–${time(context, n.end)}")
            .setSubText(if (before) "to class" else "left in class")
            .setWhen(if (before) n.start else n.end)
            .setShowWhen(true)
            .setUsesChronometer(true)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setCategory(Notification.CATEGORY_EVENT)
            .setContentIntent(launch(context))
        if (Build.VERSION.SDK_INT >= 24) b.setChronometerCountDown(true)
        if (Build.VERSION.SDK_INT >= 26) b.setTimeoutAfter(n.end - now)
        // Notification.EXTRA_REQUEST_PROMOTED_ONGOING, which is what makes it a
        // Live Update on Android 16; older versions ignore it.
        b.addExtras(Bundle().apply { putBoolean("android.requestPromotedOngoing", true) })
        try {
            manager.notify(NOTIFICATION, b.build())
        } catch (_: SecurityException) {
            // Notifications are off; the widget still shows the class.
        }
    }
}

class NextClassWidget : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        Glance.refresh(context)
    }
}

/** The alarm at each turn of the next class. */
class GlanceTick : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        Glance.refresh(context)
    }
}
