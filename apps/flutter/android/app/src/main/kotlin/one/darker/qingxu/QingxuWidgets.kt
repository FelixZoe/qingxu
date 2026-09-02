package one.darker.qingxu

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.SystemClock
import android.view.View
import android.widget.RemoteViews
import org.json.JSONArray
import java.text.SimpleDateFormat
import java.util.Locale
import java.util.TimeZone

internal object QingxuWidgetStore {
    private const val NAME = "qingxu_widget_snapshot"

    fun save(context: Context, payload: Map<String, Any?>) {
        @Suppress("UNCHECKED_CAST")
        val pomodoro = payload["pomodoro"] as? Map<String, Any?> ?: emptyMap()
        val titles = payload["todayTaskTitles"] as? List<*> ?: emptyList<Any?>()
        context.getSharedPreferences(NAME, Context.MODE_PRIVATE).edit()
            .putInt("taskCount", (payload["todayTaskCount"] as? Number)?.toInt() ?: 0)
            .putString("taskTitles", JSONArray(titles.take(3)).toString())
            .putString("mode", pomodoro["mode"] as? String ?: "focus")
            .putString("status", pomodoro["status"] as? String ?: "idle")
            .putString("direction", pomodoro["timerDirection"] as? String ?: "countdown")
            .putInt("remaining", (pomodoro["remainingSeconds"] as? Number)?.toInt() ?: 25 * 60)
            .putString("endsAt", pomodoro["endsAt"] as? String)
            .putString("startedAt", pomodoro["startedAt"] as? String)
            .putLong("savedAt", System.currentTimeMillis())
            .apply()
    }

    fun load(context: Context): Snapshot {
        val prefs = context.getSharedPreferences(NAME, Context.MODE_PRIVATE)
        val array = runCatching { JSONArray(prefs.getString("taskTitles", "[]")) }.getOrNull()
        val titles = buildList {
            if (array != null) for (index in 0 until array.length()) add(array.optString(index))
        }.filter { it.isNotBlank() }
        return Snapshot(
            taskCount = prefs.getInt("taskCount", 0),
            taskTitles = titles,
            mode = prefs.getString("mode", "focus") ?: "focus",
            status = prefs.getString("status", "idle") ?: "idle",
            direction = prefs.getString("direction", "countdown") ?: "countdown",
            remaining = prefs.getInt("remaining", 25 * 60),
            endsAtMillis = parseMillis(prefs.getString("endsAt", null)),
            startedAtMillis = parseMillis(prefs.getString("startedAt", null)),
            savedAtMillis = prefs.getLong("savedAt", System.currentTimeMillis())
        )
    }

    private fun parseMillis(value: String?): Long? {
        if (value.isNullOrBlank()) return null
        val normalized = value.replace(Regex("\\.(\\d{3})\\d*Z$"), ".$1Z")
        return runCatching {
            SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", Locale.US).apply {
                timeZone = TimeZone.getTimeZone("UTC")
            }.parse(normalized)?.time
        }.getOrNull()
    }
}

internal data class Snapshot(
    val taskCount: Int,
    val taskTitles: List<String>,
    val mode: String,
    val status: String,
    val direction: String,
    val remaining: Int,
    val endsAtMillis: Long?,
    val startedAtMillis: Long?,
    val savedAtMillis: Long
)

internal object QingxuWidgetRenderer {
    fun updateAll(context: Context) {
        val manager = AppWidgetManager.getInstance(context)
        updateToday(context, manager, manager.getAppWidgetIds(ComponentName(context, TodayWidgetProvider::class.java)))
        updateFocus(context, manager, manager.getAppWidgetIds(ComponentName(context, FocusWidgetProvider::class.java)))
    }

    fun updateToday(context: Context, manager: AppWidgetManager, ids: IntArray) {
        val snapshot = QingxuWidgetStore.load(context)
        ids.forEach { id ->
            val views = RemoteViews(context.packageName, R.layout.widget_today)
            views.setTextViewText(R.id.widget_today_count, snapshot.taskCount.toString())
            views.setTextViewText(
                R.id.widget_today_summary,
                snapshot.taskTitles.firstOrNull() ?: if (snapshot.taskCount == 0) "今天已清空" else "还有 ${snapshot.taskCount} 项待办"
            )
            bindTask(views, R.id.widget_task_1, snapshot.taskTitles.getOrNull(0))
            bindTask(views, R.id.widget_task_2, snapshot.taskTitles.getOrNull(1))
            bindTask(views, R.id.widget_task_3, snapshot.taskTitles.getOrNull(2))
            views.setOnClickPendingIntent(R.id.widget_today_root, openApp(context))
            manager.updateAppWidget(id, views)
        }
    }

    fun updateFocus(context: Context, manager: AppWidgetManager, ids: IntArray) {
        val snapshot = QingxuWidgetStore.load(context)
        ids.forEach { id ->
            val views = RemoteViews(context.packageName, R.layout.widget_focus)
            val title = when (snapshot.mode) {
                "shortBreak" -> "短暂休息"
                "longBreak" -> "长休息"
                else -> if (snapshot.direction == "countUp") "正计时" else "专注"
            }
            views.setTextViewText(R.id.widget_focus_title, title)
            views.setTextViewText(R.id.widget_focus_status, when (snapshot.status) {
                "running" -> "正在实时计时"
                "paused" -> "已暂停"
                else -> "准备开始"
            })
            bindChronometer(views, snapshot)
            views.setOnClickPendingIntent(R.id.widget_focus_root, openApp(context))
            manager.updateAppWidget(id, views)
        }
    }

    private fun bindTask(views: RemoteViews, id: Int, title: String?) {
        views.setViewVisibility(id, if (title.isNullOrBlank()) View.GONE else View.VISIBLE)
        if (!title.isNullOrBlank()) views.setTextViewText(id, "○  $title")
    }

    private fun bindChronometer(views: RemoteViews, snapshot: Snapshot) {
        val running = snapshot.status == "running"
        views.setViewVisibility(R.id.widget_focus_timer, if (running) View.VISIBLE else View.GONE)
        views.setViewVisibility(R.id.widget_focus_static_time, if (running) View.GONE else View.VISIBLE)
        if (!running) {
            views.setTextViewText(R.id.widget_focus_static_time, format(snapshot.remaining))
            return
        }
        val nowWall = System.currentTimeMillis()
        val nowElapsed = SystemClock.elapsedRealtime()
        val isCountUp = snapshot.direction == "countUp"
        val base = if (isCountUp) {
            val started = snapshot.startedAtMillis ?: (snapshot.savedAtMillis - snapshot.remaining * 1000L)
            nowElapsed - (nowWall - started).coerceAtLeast(0L)
        } else {
            val ends = snapshot.endsAtMillis ?: (snapshot.savedAtMillis + snapshot.remaining * 1000L)
            nowElapsed + (ends - nowWall).coerceAtLeast(0L)
        }
        views.setChronometer(R.id.widget_focus_timer, base, null, true)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            views.setChronometerCountDown(R.id.widget_focus_timer, !isCountUp)
        }
    }

    private fun format(seconds: Int) = "%02d:%02d".format(seconds.coerceAtLeast(0) / 60, seconds.coerceAtLeast(0) % 60)

    private fun openApp(context: Context): PendingIntent {
        val intent = context.packageManager.getLaunchIntentForPackage(context.packageName)
            ?: Intent(context, MainActivity::class.java)
        intent.addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        return PendingIntent.getActivity(context, 0, intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
    }
}

class TodayWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        QingxuWidgetRenderer.updateToday(context, manager, ids)
    }
}

class FocusWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        QingxuWidgetRenderer.updateFocus(context, manager, ids)
    }
}
