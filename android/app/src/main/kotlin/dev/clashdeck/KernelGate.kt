package dev.clashdeck

/**
 * 「内核是否真的在跑」的纯逻辑。
 *
 * 快照里的 running/starting 可能因进程被强停而残留（adb force-stop、
 * 系统回收都不会走 Service.onDestroy），所以磁贴、小组件与 ACTION_START
 * 都必须结合进程存活来判断，不能只看 prefs。
 */
object KernelGate {
    fun isActive(state: String, serviceAlive: Boolean, pid: Int, pidAlive: Boolean): Boolean {
        if (state != RuntimePrefs.STATE_RUNNING && state != RuntimePrefs.STATE_STARTING) return false
        return serviceAlive || (pid > 0 && pidAlive)
    }

    /** stale 的 running/starting 不能吞掉启动动作。 */
    fun shouldSwallowStart(
        state: String,
        serviceAlive: Boolean,
        pid: Int,
        pidAlive: Boolean,
    ): Boolean = isActive(state, serviceAlive, pid, pidAlive)
}