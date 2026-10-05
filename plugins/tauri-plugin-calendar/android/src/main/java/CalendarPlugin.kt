package ph.intportal.calendar

import android.Manifest
import android.app.Activity
import android.content.ContentUris
import android.content.ContentValues
import android.net.Uri
import android.provider.CalendarContract
import android.provider.CalendarContract.Calendars
import android.provider.CalendarContract.Events
import android.provider.CalendarContract.Instances
import app.tauri.PermissionState
import app.tauri.annotation.Command
import app.tauri.annotation.InvokeArg
import app.tauri.annotation.Permission
import app.tauri.annotation.PermissionCallback
import app.tauri.annotation.TauriPlugin
import app.tauri.plugin.Invoke
import app.tauri.plugin.JSArray
import app.tauri.plugin.JSObject
import app.tauri.plugin.Plugin
import java.util.TimeZone

@InvokeArg
class RangeArgs {
    var from: Double = 0.0
    var to: Double = 0.0
}

@InvokeArg
class ClassEvent {
    var title: String = ""
    var notes: String = ""
    var start: Double = 0.0
    var end: Double = 0.0
}

@InvokeArg
class SyncArgs {
    var from: Double = 0.0
    var to: Double = 0.0
    var events: List<ClassEvent> = listOf()
}

/**
 * The phone's own calendar, through CalendarContract: the student's events
 * (so the coach counts them as busy) and an IntPortal calendar the app owns
 * for their classes, a local one that stays on the phone.
 */
@TauriPlugin(
    permissions = [Permission(strings = [Manifest.permission.READ_CALENDAR, Manifest.permission.WRITE_CALENDAR], alias = "calendar")],
)
class CalendarPlugin(private val activity: Activity) : Plugin(activity) {
    private val resolver get() = activity.contentResolver
    private val prefs get() = activity.getSharedPreferences("calendar", Activity.MODE_PRIVATE)

    private fun access(): String = when (getPermissionState("calendar")) {
        PermissionState.GRANTED -> "granted"
        PermissionState.DENIED -> "denied"
        else -> "not_asked"
    }

    private fun resolveAccess(invoke: Invoke) = invoke.resolve(JSObject().put("status", access()))

    @Command
    fun status(invoke: Invoke) = resolveAccess(invoke)

    @Command
    fun request(invoke: Invoke) {
        if (access() == "granted") resolveAccess(invoke) else requestPermissionForAlias("calendar", invoke, "requested")
    }

    @PermissionCallback
    private fun requested(invoke: Invoke) = resolveAccess(invoke)

    /** The student's own events in the range, leaving out the app's calendar. */
    @Command
    fun events(invoke: Invoke) {
        val args = invoke.parseArgs(RangeArgs::class.java)
        val found = JSArray()
        if (access() == "granted") {
            val owned = prefs.getLong(OWNED, -1)
            val uri = Instances.CONTENT_URI.buildUpon().also {
                ContentUris.appendId(it, args.from.toLong())
                ContentUris.appendId(it, args.to.toLong())
            }.build()
            resolver.query(
                uri, arrayOf(Instances.TITLE, Instances.BEGIN, Instances.END, Instances.ALL_DAY),
                "${Instances.CALENDAR_ID} != ?", arrayOf(owned.toString()), null,
            )?.use { c ->
                while (c.moveToNext()) {
                    found.put(JSObject().put("title", c.getString(0) ?: "").put("start", c.getLong(1)).put("end", c.getLong(2)).put("allDay", c.getInt(3) == 1))
                }
            }
        }
        invoke.resolve(JSObject().put("events", found))
    }

    /** Replaces the IntPortal calendar's events in the range with these. */
    @Command
    fun syncClasses(invoke: Invoke) {
        val args = invoke.parseArgs(SyncArgs::class.java)
        if (access() != "granted") return invoke.reject("Calendar access is off.")
        val calendar = owned()
        resolver.delete(
            Events.CONTENT_URI, "${Events.CALENDAR_ID} = ? AND ${Events.DTSTART} >= ? AND ${Events.DTSTART} < ?",
            arrayOf(calendar.toString(), args.from.toLong().toString(), args.to.toLong().toString()),
        )
        val zone = TimeZone.getDefault().id
        resolver.bulkInsert(Events.CONTENT_URI, args.events.map {
            ContentValues().apply {
                put(Events.CALENDAR_ID, calendar)
                put(Events.TITLE, it.title)
                put(Events.DESCRIPTION, it.notes)
                put(Events.DTSTART, it.start.toLong())
                put(Events.DTEND, it.end.toLong())
                put(Events.EVENT_TIMEZONE, zone)
            }
        }.toTypedArray())
        invoke.resolve(JSObject().put("count", args.events.size))
    }

    /** The app's own calendar, made on first use. Its id is remembered, so
     *  renaming it in the Calendar app doesn't make a second one. */
    private fun owned(): Long {
        val id = prefs.getLong(OWNED, -1)
        if (id >= 0) {
            resolver.query(ContentUris.withAppendedId(Calendars.CONTENT_URI, id), arrayOf(Calendars._ID), null, null, null)?.use {
                if (it.moveToFirst()) return id
            }
        }
        // Only a sync adapter may add a calendar; a local account is ours to act for.
        val uri = Calendars.CONTENT_URI.buildUpon()
            .appendQueryParameter(CalendarContract.CALLER_IS_SYNCADAPTER, "true")
            .appendQueryParameter(Calendars.ACCOUNT_NAME, ACCOUNT)
            .appendQueryParameter(Calendars.ACCOUNT_TYPE, CalendarContract.ACCOUNT_TYPE_LOCAL)
            .build()
        val made: Uri = resolver.insert(uri, ContentValues().apply {
            put(Calendars.ACCOUNT_NAME, ACCOUNT)
            put(Calendars.ACCOUNT_TYPE, CalendarContract.ACCOUNT_TYPE_LOCAL)
            put(Calendars.NAME, "IntPortal")
            put(Calendars.CALENDAR_DISPLAY_NAME, "IntPortal")
            put(Calendars.CALENDAR_COLOR, 0xFF7A1229.toInt())
            put(Calendars.CALENDAR_ACCESS_LEVEL, Calendars.CAL_ACCESS_OWNER)
            put(Calendars.OWNER_ACCOUNT, ACCOUNT)
            put(Calendars.VISIBLE, 1)
            put(Calendars.SYNC_EVENTS, 1)
            put(Calendars.CALENDAR_TIME_ZONE, TimeZone.getDefault().id)
        }) ?: error("Couldn't make the IntPortal calendar.")
        return ContentUris.parseId(made).also { prefs.edit().putLong(OWNED, it).apply() }
    }

    private companion object {
        const val OWNED = "intportal.calendar.id"
        const val ACCOUNT = "IntPortal"
    }
}
