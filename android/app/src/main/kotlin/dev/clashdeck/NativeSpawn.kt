package dev.clashdeck

/**
 * fork + execv 的 JNI 封装（见 `src/main/cpp/spawn.c`）。
 *
 * 为什么需要它：Java 的 `ProcessBuilder` 在 Android 上走 posix_spawn +
 * POSIX_SPAWN_CLOEXEC_DEFAULT，会把除 stdio 之外的所有 fd 关掉，于是 VpnService
 * 建好的 TUN fd 在子进程里是无效的（内核会报 `bad file descriptor`）。
 * 自己 fork 出来的子进程继承完整 fd 表，exec 只关 FD_CLOEXEC 的 fd。
 */
object NativeSpawn {
    init {
        System.loadLibrary("clashdeckspawn")
    }

    /**
     * 拉起 [binary]，把 [tunFd] 原样继承过去，stdout/stderr 重定向到 [logPath]。
     *
     * @return 子进程 pid；负数是 `-errno`
     */
    external fun spawn(
        binary: String,
        argv: Array<String>,
        tunFd: Int,
        logPath: String?,
        workDir: String?,
    ): Int

    /** 阻塞回收 [pid]，返回退出码（128+signal 表示被信号杀死）；负数是 `-errno`。 */
    external fun waitPid(pid: Int): Int

    /** 给 [pid] 发信号，返回 0 表示成功。 */
    external fun sendSignal(pid: Int, signal: Int): Int
}
