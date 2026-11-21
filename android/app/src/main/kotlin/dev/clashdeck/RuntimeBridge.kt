package dev.clashdeck

import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.MethodChannel

/**
 * Kotlin 与 Dart 之间的双向通道持有者。
 *
 * 之所以是双向：TUN 的 fd 只有 [ClashVpnService] 建立 VPN 之后才知道，
 * 而运行配置（YAML）必须由 Dart 侧统一生成（保证只有一份配置生成逻辑）。
 * 所以流程是 Kotlin 起来 → 建 TUN → 回调 Dart 要配置 → 写盘 → 拉内核。
 */
object RuntimeBridge {
    private const val CHANNEL = "dev.clashdeck/runtime"

    private val main = Handler(Looper.getMainLooper())

    @Volatile
    private var channel: MethodChannel? = null

    fun attach(value: MethodChannel) {
        channel = value
    }

    fun detach(value: MethodChannel) {
        if (channel === value) channel = null
    }

    fun channelName(): String = CHANNEL

    /**
     * 请求 Dart 侧用真实 fd 生成运行配置。
     * 回调在主线程；失败时传 null。
     */
    fun requestConfig(fd: Int, port: Int, secret: String?, tunStack: String, done: (String?) -> Unit) {
        val current = channel
        if (current == null) {
            MihomoCore.log("Dart 通道未就绪，无法生成运行配置")
            done(null)
            return
        }
        main.post {
            current.invokeMethod(
                "buildRuntimeConfig",
                mapOf("fd" to fd, "port" to port, "secret" to secret, "tunStack" to tunStack),
                object : MethodChannel.Result {
                    override fun success(result: Any?) {
                        done(result as? String)
                    }

                    override fun error(code: String, message: String?, details: Any?) {
                        MihomoCore.log("生成运行配置失败：$code $message")
                        done(null)
                    }

                    override fun notImplemented() {
                        MihomoCore.log("Dart 未实现 buildRuntimeConfig")
                        done(null)
                    }
                },
            )
        }
    }

    /** 把内核/VPN 状态推给 Dart。 */
    fun notifyState(state: String, message: String? = null, pid: Int? = null) {
        val current = channel ?: return
        main.post {
            current.invokeMethod(
                "onRuntimeState",
                mapOf("state" to state, "message" to message, "pid" to pid),
            )
        }
    }
}
