package dev.clashdeck

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews

/**
 * 2×1 桌面小组件：只读 [RuntimePrefs] 快照，启停走无界面 [ClashActionActivity]。
 * 内核状态变化时由 [ClashVpnService] 调 [refresh] 主动刷新，不依赖定时更新。
 */
class ClashWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        for (id in appWidgetIds) {
            appWidgetManager.updateAppWidget(id, buildViews(context))
        }
    }

    private fun buildViews(context: Context): RemoteViews {
        val running = RuntimePrefs.isActive(context)
        val state = RuntimePrefs.kernelState(context)
        val profile = RuntimePrefs.profileName(context)?.takeIf { it.isNotBlank() }
        val exit = RuntimePrefs.globalExit(context)?.takeIf { it.isNotBlank() }
        val views = RemoteViews(context.packageName, R.layout.clash_widget)
        views.setTextViewText(R.id.widget_title, WidgetCopy.title(running, state))
        views.setTextViewText(
            R.id.widget_subtitle,
            WidgetCopy.subtitle(
                hasSnapshot = RuntimePrefs.loadStart(context) != null,
                profile = profile,
                exit = exit,
            ),
        )
        views.setImageViewResource(
            R.id.widget_dot,
            if (running) R.drawable.widget_dot_on else R.drawable.widget_dot_off,
        )
        views.setInt(
            R.id.widget_toggle,
            "setBackgroundResource",
            if (running) R.drawable.widget_button_on else R.drawable.widget_button_off,
        )
        views.setImageViewResource(
            R.id.widget_toggle,
            if (running) R.drawable.ic_widget_stop else R.drawable.ic_widget_play,
        )
        val action = if (running) ClashActionActivity.ACTION_STOP else ClashActionActivity.ACTION_START
        val toggleIntent = Intent(context, ClashActionActivity::class.java).apply {
            this.action = action
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        }
        views.setOnClickPendingIntent(
            R.id.widget_toggle,
            PendingIntent.getActivity(
                context,
                if (running) 4 else 5,
                toggleIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            ),
        )
        views.setOnClickPendingIntent(
            R.id.widget_root,
            PendingIntent.getActivity(
                context,
                6,
                Intent(context, MainActivity::class.java),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            ),
        )
        return views
    }

    companion object {
        /** 内核状态变化后刷新所有已添加的小组件。 */
        fun refresh(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            val ids = manager.getAppWidgetIds(ComponentName(context, ClashWidgetProvider::class.java))
            if (ids.isEmpty()) return
            val provider = ClashWidgetProvider()
            provider.onUpdate(context, manager, ids)
        }
    }
}
