package dev.clashdeck

import android.content.Context
import android.content.SharedPreferences

/**
 * 内核启动参数与运行状态的本地快照。
 *
 * 用途：磁贴 / 通知 / 桌面小组件在没有 Flutter engine 的时候也能读到最后一次
 * 启动参数并展示真实状态。参数只在用户于 App 内点「启动」时写入，状态由
 * [ClashVpnService] 维护。
 *
 * 注意：快照里有 controller secret，只能留在应用私有目录，不能进日志或通知。
 */
object RuntimePrefs {
    private const val FILE = "clashdeck_runtime"
    private const val KEY_WORK_DIR = "workDir"
    private const val KEY_PORT = "port"
    private const val KEY_SECRET = "secret"
    private const val KEY_PROXY_MODE = "proxyMode"
    private const val KEY_ROUTE_MODE = "routeMode"
    private const val KEY_ROUTE_APPS = "routeApps"
    private const val KEY_MTU = "mtu"
    private const val KEY_TUN_ADDRESS = "tunAddress"
    private const val KEY_IPV6 = "ipv6"
    private const val KEY_PROFILE_NAME = "profileName"
    private const val KEY_GLOBAL_EXIT = "globalExit"
    private const val KEY_KERNEL_STATE = "kernelState"
    private const val KEY_KERNEL_ERROR = "kernelError"
    private const val KEY_KERNEL_PID = "kernelPid"
    private const val KEY_KERNEL_STARTED_AT = "kernelStartedAt"

    const val STATE_STOPPED = "stopped"
    const val STATE_STARTING = "starting"
    const val STATE_RUNNING = "running"
    const val STATE_STOPPING = "stopping"
    const val STATE_ERROR = "error"

    private fun prefs(context: Context): SharedPreferences =
        context.applicationContext.getSharedPreferences(FILE, Context.MODE_PRIVATE)

    /** 保存一次启动参数（由 MainActivity 在拉起 service 前调用）。 */
    fun saveStart(context: Context, arguments: Map<*, *>) {
        val routeApps = (arguments["routeApps"] as? List<*>)?.mapNotNull { it as? String }
            ?: emptyList()
        prefs(context).edit()
            .putString(KEY_WORK_DIR, arguments["workDir"] as? String)
            .putInt(KEY_PORT, (arguments["port"] as? Number)?.toInt() ?: 9090)
            .putString(KEY_SECRET, arguments["secret"] as? String)
            .putString(KEY_PROXY_MODE, arguments["proxyMode"] as? String ?: "tun")
            .putString(KEY_ROUTE_MODE, arguments["routeMode"] as? String ?: "all")
            .putStringSet(KEY_ROUTE_APPS, routeApps.toSet())
            .putInt(KEY_MTU, (arguments["mtu"] as? Number)?.toInt() ?: 9000)
            .putString(KEY_TUN_ADDRESS, arguments["tunAddress"] as? String)
            .putBoolean(KEY_IPV6, arguments["ipv6"] as? Boolean ?: false)
            .putString(KEY_PROFILE_NAME, arguments["profileName"] as? String ?: "")
            .putString(KEY_GLOBAL_EXIT, arguments["globalExit"] as? String ?: "")
            .apply()
    }

    /** 读取上一次启动参数；从未在 App 内启动过时返回 null。 */
    fun loadStart(context: Context): Map<String, Any?>? {
        val p = prefs(context)
        val workDir = p.getString(KEY_WORK_DIR, null) ?: return null
        return mapOf(
            "workDir" to workDir,
            "port" to p.getInt(KEY_PORT, 9090),
            "secret" to p.getString(KEY_SECRET, null),
            "proxyMode" to p.getString(KEY_PROXY_MODE, "tun"),
            "routeMode" to p.getString(KEY_ROUTE_MODE, "all"),
            "routeApps" to (p.getStringSet(KEY_ROUTE_APPS, emptySet()) ?: emptySet()).toList(),
            "mtu" to p.getInt(KEY_MTU, 9000),
            "tunAddress" to p.getString(KEY_TUN_ADDRESS, null),
            "ipv6" to p.getBoolean(KEY_IPV6, false),
            "profileName" to p.getString(KEY_PROFILE_NAME, ""),
            "globalExit" to p.getString(KEY_GLOBAL_EXIT, ""),
        )
    }

    /** service 更新状态，供磁贴 / 通知 / Widget 直接读取。 */
    fun setKernel(context: Context, state: String, pid: Int? = null, error: String? = null) {
        val p = prefs(context)
        val editor = p.edit().putString(KEY_KERNEL_STATE, state)
        when (state) {
            STATE_RUNNING -> {
                editor.putInt(KEY_KERNEL_PID, pid ?: p.getInt(KEY_KERNEL_PID, -1))
                if (p.getLong(KEY_KERNEL_STARTED_AT, 0) == 0L) {
                    editor.putLong(KEY_KERNEL_STARTED_AT, System.currentTimeMillis())
                }
                editor.putString(KEY_KERNEL_ERROR, null)
            }

            STATE_STOPPED -> editor
                .putInt(KEY_KERNEL_PID, -1)
                .putLong(KEY_KERNEL_STARTED_AT, 0)
                .putString(KEY_KERNEL_ERROR, null)

            STATE_ERROR -> editor
                .putInt(KEY_KERNEL_PID, -1)
                .putString(KEY_KERNEL_ERROR, error)

            else -> if (error != null) editor.putString(KEY_KERNEL_ERROR, error)
        }
        editor.apply()
    }

    fun kernelState(context: Context): String =
        prefs(context).getString(KEY_KERNEL_STATE, STATE_STOPPED) ?: STATE_STOPPED

    fun kernelError(context: Context): String? =
        prefs(context).getString(KEY_KERNEL_ERROR, null)

    fun kernelPid(context: Context): Int = prefs(context).getInt(KEY_KERNEL_PID, -1)

    fun isRunning(context: Context): Boolean = kernelState(context) == STATE_RUNNING
}
