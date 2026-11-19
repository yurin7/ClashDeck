package dev.clashdeck

/**
 * 小组件/磁贴的纯文案逻辑，便于 JVM 单测。
 *
 * 快照来自 [RuntimePrefs]（由 Dart 启动内核时写入）；没有快照说明用户还没在 App 内启动过内核，
 * 此时小组件点开也只是提醒，不应该伪装成「已停止」的空状态。
 */
object WidgetCopy {
    fun title(running: Boolean, state: String): String = when {
        running -> "已连接"
        state == RuntimePrefs.STATE_STARTING -> "启动中"
        state == RuntimePrefs.STATE_ERROR -> "启动失败"
        else -> "已停止"
    }

    fun subtitle(hasSnapshot: Boolean, profile: String?, exit: String?): String {
        if (!hasSnapshot) return "请先在 App 内启动一次内核"
        val parts = listOfNotNull(
            profile?.takeIf { it.isNotBlank() },
            exit?.takeIf { it.isNotBlank() },
        )
        return if (parts.isEmpty()) "轻点打开 ClashDeck" else parts.joinToString(" · ")
    }
}