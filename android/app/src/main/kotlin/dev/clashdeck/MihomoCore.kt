package dev.clashdeck

import android.system.OsConstants
import android.util.Log
import java.io.File
import java.io.RandomAccessFile
import java.util.ArrayDeque

/**
 * mihomo 内核子进程的托管者。
 *
 * 内核是一个独立进程（[nativeLibraryDir/libmihomo.so]，纯 Go 静态二进制，借
 * nativeLibraryDir 的可执行权限绕开 Android 10+ 对 app 私有目录的 W^X 限制）。
 * TUN 的 fd 由 [ClashVpnService] 建立后传进来，通过 [NativeSpawn] 的 fork+exec
 * 原样继承（Java 的 ProcessBuilder 会把它关掉，见 spawn.c 的注释）。
 *
 * 内核的 stdout/stderr 被重定向到 `<workDir>/core.log`，这里做增量 tail 填进
 * 环形缓冲，日志既能给 UI 看，也能保留启动期（REST 还没起来时）的报错。
 */
object MihomoCore {
    private const val TAG = "ClashDeck.Core"

    /** 日志环形缓冲上限（行）。 */
    private const val MAX_LOG_LINES = 500

    /** 内核 stdout/stderr 落盘的文件名（相对 workDir）。 */
    private const val LOG_FILE_NAME = "core.log"

    private val logs = ArrayDeque<String>()
    private val lock = Any()

    @Volatile
    private var pidValue: Int = -1

    @Volatile
    private var running: Boolean = false

    /** 内核进程 pid，-1 表示没在跑。 */
    val pid: Int get() = pidValue

    val isRunning: Boolean get() = running

    fun log(line: String) {
        val text = line.trimEnd()
        if (text.isEmpty()) return
        synchronized(lock) {
            logs.addLast(text)
            while (logs.size > MAX_LOG_LINES) logs.removeFirst()
        }
        Log.i(TAG, text)
    }

    fun recentLogs(limit: Int = 200): List<String> = synchronized(lock) {
        if (limit <= 0) return@synchronized emptyList<String>()
        val all = logs.toList()
        return@synchronized if (all.size <= limit) all else all.subList(all.size - limit, all.size)
    }

    fun clearLogs() = synchronized(lock) { logs.clear() }

    /**
     * 启动内核。返回 null 表示已拉起，否则为错误信息。
     *
     * @param binary `nativeLibraryDir/libmihomo.so`
     * @param workDir `-d` 参数（geo 数据库、缓存都落在这里）
     * @param configFile `-f` 参数（运行期生成的配置，里面写着 `tun.file-descriptor: <tunFd>`）
     * @param tunFd VpnService 建立并 detach 出来的 TUN fd
     * @param protectSocket system / mixed 出站套接字的 Android VPN 保护入口
     */
    fun start(binary: File, workDir: File, configFile: File, tunFd: Int, protectSocket: String? = null): String? {
        if (isRunning) return "内核已在运行"
        if (!binary.exists()) return "找不到内核文件：${binary.absolutePath}"
        if (!configFile.exists()) return "找不到运行配置：${configFile.absolutePath}"
        if (tunFd < 0) return "TUN fd 无效：$tunFd" // 0 = 仅代理端口模式（不接管流量）
        workDir.mkdirs()

        val logFile = File(workDir, LOG_FILE_NAME)
        logFile.delete()
        val baseArgs = arrayOf(
            binary.absolutePath,
            "-d", workDir.absolutePath,
            "-f", configFile.absolutePath,
        )
        val argv = if (protectSocket == null) baseArgs else
            baseArgs + arrayOf("-clashdeck-protect-socket", protectSocket)
        log("启动内核：" + baseArgs.joinToString(" ") + "（fd=" + tunFd + "）")

        val spawned = try {
            NativeSpawn.spawn(
                binary.absolutePath,
                argv,
                tunFd,
                logFile.absolutePath,
                workDir.absolutePath,
            )
        } catch (t: Throwable) {
            log("native spawn 抛异常：${t.message}")
            return t.message ?: t.toString()
        }
        if (spawned <= 0) {
            log("native spawn 失败，返回值 $spawned")
            return "启动内核失败：errno ${-spawned}"
        }

        pidValue = spawned
        running = true
        log("内核进程 pid=$spawned，日志 ${logFile.absolutePath}")

        Thread({ tailLog(logFile) }, "mihomo-log").apply { isDaemon = true }.start()
        Thread({ watch(spawned) }, "mihomo-watch").apply { isDaemon = true }.start()
        return null
    }

    /** 停止内核；[graceMs] 后仍未退出则强杀。 */
    fun stop(graceMs: Long = 1500) {
        val current = pidValue
        if (current <= 0) {
            running = false
            return
        }
        // 先把自己的状态清掉：watch() 看到 pid 不再是自己，就知道这是主动停止，
        // 不会把正常的 stop 当成"内核崩溃"上报给 Dart。
        running = false
        pidValue = -1
        log("正在停止内核 pid=$current")
        NativeSpawn.sendSignal(current, OsConstants.SIGTERM)
        Thread({
            try {
                Thread.sleep(graceMs)
            } catch (_: InterruptedException) {
            }
            if (File("/proc/$current").exists()) {
                log("内核未响应，强制结束")
                NativeSpawn.sendSignal(current, OsConstants.SIGKILL)
            }
        }, "mihomo-killer").apply { isDaemon = true }.start()
    }

    /** 增量读内核日志文件，直到进程结束且文件读空。 */
    private fun tailLog(logFile: File) {
        var offset = 0L
        val partial = StringBuilder()
        while (true) {
            var readSomething = false
            try {
                if (logFile.exists()) {
                    val length = logFile.length()
                    if (length > offset) {
                        RandomAccessFile(logFile, "r").use { file ->
                            file.seek(offset)
                            val want = (length - offset).coerceAtMost(64L * 1024).toInt()
                            val buffer = ByteArray(want)
                            val read = file.read(buffer)
                            if (read > 0) {
                                offset += read
                                partial.append(String(buffer, 0, read))
                                readSomething = true
                                emitLines(partial)
                            }
                        }
                    }
                }
            } catch (t: Throwable) {
                log("读取内核日志失败：${t.message}")
                return
            }
            if (!running && !readSomething && logFile.length() <= offset) return
            if (!readSomething) {
                try {
                    Thread.sleep(120)
                } catch (_: InterruptedException) {
                    return
                }
            }
        }
    }

    private fun emitLines(partial: StringBuilder) {
        while (true) {
            val index = partial.indexOf("\n")
            if (index < 0) return
            val line = partial.substring(0, index)
            partial.delete(0, index + 1)
            log(line)
        }
    }

    private fun watch(startedPid: Int) {
        val code = try {
            NativeSpawn.waitPid(startedPid)
        } catch (t: Throwable) {
            log("回收内核进程失败：${t.message}")
            -1
        }
        if (pidValue != startedPid) {
            // 主动停止（stop() 已清掉 pid）或已被新进程取代：不当作崩溃上报。
            log("内核进程已退出（主动停止），code=$code")
            return
        }
        running = false
        pidValue = -1
        log("内核进程退出，code=$code")
        RuntimeBridge.notifyState("exited", message = "内核退出（code=$code）")
    }
}
