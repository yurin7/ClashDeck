package dev.clashdeck

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.net.VpnService
import android.os.Build
import android.os.ParcelFileDescriptor
import android.system.Os
import android.system.OsConstants
import java.io.File

/**
 * 建立 TUN 并把 fd 交给内核子进程。
 *
 * 为什么用子进程而不是 JNI：mihomo 官方没有 Android AAR，Gomobile 绑定的 ABI
 * 需要自己维护；而 mihomo 支持 `tun.file-descriptor`，把 VpnService 建好的
 * TUN 文件描述符直接交给一个纯 Go 静态二进制即可。
 */
class ClashVpnService : VpnService() {

    companion object {
        const val ACTION_START = "dev.clashdeck.action.START"
        const val ACTION_STOP = "dev.clashdeck.action.STOP"

        const val EXTRA_WORK_DIR = "workDir"
        const val EXTRA_PORT = "port"
        const val EXTRA_SECRET = "secret"

        /** `tun` = 建 VPN 接管流量；`port` = 不接管，只开 mixed-port。 */
        const val EXTRA_PROXY_MODE = "proxyMode"

        /** `all` / `allow` / `block`，配合 [EXTRA_ROUTE_APPS]。 */
        const val EXTRA_ROUTE_MODE = "routeMode"

        const val EXTRA_ROUTE_APPS = "routeApps"
        const val EXTRA_MTU = "mtu"

        private const val CHANNEL_ID = "clashdeck-core"
        private const val NOTIFICATION_ID = 0x4344

        private const val TUN_ADDRESS = "172.19.0.1"
        private const val TUN_PREFIX = 30
        private const val TUN_DNS = "172.19.0.2"
        private const val TUN_ADDRESS6 = "fdfe:dcba:9876::1"
        private const val TUN_PREFIX6 = 126
        private const val TUN_MTU = 9000

        /** VPN + 内核是否都在跑。 */
        @Volatile
        var running: Boolean = false
            private set

        /** 上一次启动失败的原因。 */
        @Volatile
        var lastError: String? = null
            private set
    }

    private var bootThread: Thread? = null
    private var tunFd: Int = -1

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> {
                shutdown("用户断开")
                return START_NOT_STICKY
            }

            ACTION_START -> {
                promoteToForeground()
                val workDir = intent.getStringExtra(EXTRA_WORK_DIR) ?: filesDir.absolutePath
                val port = intent.getIntExtra(EXTRA_PORT, 9090)
                val secret = intent.getStringExtra(EXTRA_SECRET)
                val proxyMode = intent.getStringExtra(EXTRA_PROXY_MODE) ?: "tun"
                val routeMode = intent.getStringExtra(EXTRA_ROUTE_MODE) ?: "all"
                val routeApps = intent.getStringArrayListExtra(EXTRA_ROUTE_APPS) ?: arrayListOf()
                val mtu = intent.getIntExtra(EXTRA_MTU, TUN_MTU)
                bootThread?.interrupt()
                bootThread = Thread(
                    { boot(File(workDir), port, secret, proxyMode, routeMode, routeApps, mtu) },
                    "clashdeck-boot",
                ).also {
                    it.isDaemon = true
                    it.start()
                }
                return START_NOT_STICKY
            }
        }
        return START_NOT_STICKY
    }

    override fun onRevoke() {
        shutdown("系统撤销了 VPN 授权")
        super.onRevoke()
    }

    override fun onDestroy() {
        bootThread?.interrupt()
        MihomoCore.stop()
        closeTun()
        running = false
        super.onDestroy()
    }

    // ----------------------------------------------------------------- 启动

    private fun boot(
        workDir: File,
        port: Int,
        secret: String?,
        proxyMode: String,
        routeMode: String,
        routeApps: List<String>,
        mtu: Int,
    ) {
        lastError = null
        RuntimeBridge.notifyState("starting")
        try {
            workDir.mkdirs()
            MihomoCore.stop()
            closeTun()

            // 仅代理端口模式：不建 TUN，内核只开 mixed-port / REST。
            if (proxyMode == "port") {
                MihomoCore.log("仅代理端口模式：跳过 TUN")
                RuntimeBridge.requestConfig(0, port, secret) { yaml ->
                    startCore(workDir, yaml, 0)
                }
                return
            }

            val descriptor = establishTun(routeMode, routeApps, mtu)
            if (descriptor == null) {
                fail("建立 VPN 失败：没有拿到授权或系统拒绝")
                return
            }
            val fd = handOver(descriptor)
            MihomoCore.log("TUN 已建立，fd=$fd，开始向 Dart 索取运行配置")
            RuntimeBridge.requestConfig(fd, port, secret) { yaml ->
                startCore(workDir, yaml, fd)
            }
        } catch (t: Throwable) {
            fail("启动异常：${t.message}")
        }
    }

    private fun startCore(workDir: File, yaml: String?, tunFd: Int) {
        Thread({
            try {
                if (yaml.isNullOrBlank()) {
                    fail("运行配置生成失败")
                    return@Thread
                }
                val configFile = File(workDir, "runtime.yaml")
                configFile.writeText(yaml)
                val binary = File(applicationInfo.nativeLibraryDir, "libmihomo.so")
                val error = MihomoCore.start(binary, workDir, configFile, tunFd)
                if (error != null) {
                    fail(error)
                } else {
                    running = true
                    RuntimeBridge.notifyState("running", pid = MihomoCore.pid)
                }
            } catch (t: Throwable) {
                fail("写入配置或启动内核失败：${t.message}")
            }
        }, "clashdeck-start").also {
            it.isDaemon = true
            it.start()
        }
    }

    private fun establishTun(routeMode: String, routeApps: List<String>, mtu: Int): ParcelFileDescriptor? {
        val builder = Builder()
            .setSession("ClashDeck")
            .setMtu(if (mtu > 0) mtu else TUN_MTU)
            .addAddress(TUN_ADDRESS, TUN_PREFIX)
            .addDnsServer(TUN_DNS)
            .addRoute("0.0.0.0", 0)

        // 分应用代理：allow 只让选中应用进来（自身默认不在其中，天然排除）；
        // block / all 先把自身排除掉，避免回环。
        var allowApplied = 0
        if (routeMode == "allow" && routeApps.isNotEmpty()) {
            routeApps.forEach { pkg ->
                try {
                    builder.addAllowedApplication(pkg)
                    allowApplied++
                } catch (t: Throwable) {
                    MihomoCore.log("加入代理名单失败($pkg)：${t.message}")
                }
            }
        }
        if (allowApplied == 0) {
            try {
                builder.addDisallowedApplication(packageName)
            } catch (t: Throwable) {
                MihomoCore.log("排除自身应用失败：${t.message}")
            }
            if (routeMode == "block") {
                routeApps.forEach { pkg ->
                    try {
                        builder.addDisallowedApplication(pkg)
                    } catch (t: Throwable) {
                        MihomoCore.log("排除应用失败($pkg)：${t.message}")
                    }
                }
            }
        }
        MihomoCore.log(
            "TUN 路由：mode=$routeMode，名单=${routeApps.size}，实际允许=$allowApplied，mtu=${if (mtu > 0) mtu else TUN_MTU}",
        )
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            builder.setMetered(false)
        }
        // IPv6 可选：设备不支持时忽略。
        try {
            builder.addAddress(TUN_ADDRESS6, TUN_PREFIX6)
            builder.addRoute("::", 0)
        } catch (t: Throwable) {
            MihomoCore.log("IPv6 路由添加失败（忽略）：${t.message}")
        }
        return builder.establish()
    }

    /** 清掉 CLOEXEC 再 detach，子进程才能继承这个 fd。 */
    private fun handOver(descriptor: ParcelFileDescriptor): Int {
        try {
            Os.fcntlInt(descriptor.fileDescriptor, OsConstants.F_SETFD, 0)
        } catch (t: Throwable) {
            MihomoCore.log("清除 CLOEXEC 失败：${t.message}")
        }
        val fd = descriptor.detachFd()
        tunFd = fd
        return fd
    }

    private fun fail(message: String) {
        lastError = message
        running = false
        MihomoCore.log("启动失败：$message")
        RuntimeBridge.notifyState("error", message = message)
        // 失败后的收尾不再发 "stopped"，否则会把刚报的错误状态冲掉。
        shutdown(null, notify = false)
    }

    private fun shutdown(reason: String?, notify: Boolean = true) {
        MihomoCore.stop()
        closeTun()
        running = false
        if (reason != null) MihomoCore.log("内核停止：$reason")
        if (notify) RuntimeBridge.notifyState("stopped", message = reason)
        stopForegroundCompat()
        stopSelf()
    }

    private fun closeTun() {
        val fd = tunFd
        tunFd = -1
        if (fd >= 0) {
            try {
                // Os.close 要 FileDescriptor，这里只有 raw fd：adoptFd 接管后关闭。
                ParcelFileDescriptor.adoptFd(fd).close()
            } catch (t: Throwable) {
                MihomoCore.log("关闭 TUN fd 失败：${t.message}")
            }
        }
    }

    // ------------------------------------------------------------- 前台通知

    private fun promoteToForeground() {
        val manager = getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            if (manager.getNotificationChannel(CHANNEL_ID) == null) {
                manager.createNotificationChannel(
                    NotificationChannel(CHANNEL_ID, "内核运行状态", NotificationManager.IMPORTANCE_LOW),
                )
            }
        }
        val intent = Intent(this, MainActivity::class.java)
        val pending = PendingIntent.getActivity(
            this,
            0,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        val notification = builder
            .setContentTitle("ClashDeck")
            .setContentText("内核运行中")
            .setSmallIcon(android.R.drawable.stat_sys_upload)
            .setContentIntent(pending)
            .setOngoing(true)
            .build()
        startForeground(NOTIFICATION_ID, notification)
    }

    private fun stopForegroundCompat() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } else {
            @Suppress("DEPRECATION")
            stopForeground(true)
        }
    }
}
