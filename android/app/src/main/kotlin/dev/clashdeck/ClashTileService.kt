package dev.clashdeck

import android.app.PendingIntent
import android.content.Intent
import android.graphics.drawable.Icon
import android.os.Build
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService

/**
 * 快捷设置磁贴：与通知/桌面小组件走同一个无界面入口 [ClashActionActivity]。
 * 磁贴只读 [RuntimePrefs] 快照，不直接操作内核。
 */
class ClashTileService : TileService() {
    override fun onStartListening() {
        super.onStartListening()
        refreshTile()
    }

    override fun onTileAdded() {
        super.onTileAdded()
        refreshTile()
    }

    override fun onClick() {
        super.onClick()
        val running = RuntimePrefs.isRunning(this) ||
            RuntimePrefs.kernelState(this) == RuntimePrefs.STATE_STARTING
        val action = if (running) ClashActionActivity.ACTION_STOP else ClashActionActivity.ACTION_START
        val intent = Intent(this, ClashActionActivity::class.java).apply {
            this.action = action
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            val pending = PendingIntent.getActivity(
                this,
                if (running) 2 else 3,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
            startActivityAndCollapse(pending)
        } else {
            @Suppress("DEPRECATION")
            startActivityAndCollapse(intent)
        }
        refreshTile()
    }

    private fun refreshTile() {
        val tile = qsTile ?: return
        val running = RuntimePrefs.isRunning(this)
        tile.state = if (running) Tile.STATE_ACTIVE else Tile.STATE_INACTIVE
        tile.label = "ClashDeck"
        tile.subtitle = if (running) {
            RuntimePrefs.profileName(this)?.takeIf { it.isNotBlank() } ?: "已连接"
        } else {
            "未连接"
        }
        tile.icon = Icon.createWithResource(this, R.drawable.ic_tile_clashdeck)
        tile.updateTile()
    }
}
