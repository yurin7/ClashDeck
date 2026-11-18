package dev.clashdeck

import android.app.Activity
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.BitmapDrawable
import android.graphics.drawable.Drawable
import android.net.VpnService
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream

class MainActivity : FlutterActivity() {

    companion object {
        private const val REQUEST_VPN_PERMISSION = 0x1001
        private const val ICON_SIZE = 96
    }

    private var channel: MethodChannel? = null
    private var pendingStart: Map<*, *>? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val created = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, RuntimeBridge.channelName())
        channel = created
        RuntimeBridge.attach(created)
        created.setMethodCallHandler { call, result ->
            try {
                handle(call.method, call.arguments, result)
            } catch (t: Throwable) {
                result.error("runtime", t.message ?: t.toString(), null)
            }
        }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        channel?.let { RuntimeBridge.detach(it) }
        channel = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    private fun handle(method: String, arguments: Any?, result: MethodChannel.Result) {
        when (method) {
            "start" -> requestStart(arguments as? Map<*, *> ?: emptyMap<String, Any>(), result)
            "stop" -> {
                sendServiceAction(ClashVpnService.ACTION_STOP)
                result.success(null)
            }

            "status" -> result.success(
                mapOf(
                    "running" to MihomoCore.isRunning,
                    "pid" to MihomoCore.pid,
                    "error" to ClashVpnService.lastError,
                ),
            )

            "logs" -> {
                val limit = (arguments as? Int) ?: 200
                result.success(MihomoCore.recentLogs(limit))
            }

            "clearLogs" -> {
                MihomoCore.clearLogs()
                result.success(null)
            }

            "listApps" -> result.success(listApps())

            "listAppIcons" -> listAppIcons(arguments, result)

            else -> result.notImplemented()
        }
    }

    /**
     * 已安装应用清单（分应用代理选择用）。
     *
     * 只返回"用户可见"的应用：有启动入口的用户应用 + 系统里用户装的那部分；
     * 排除自己（永远不给自己走代理）。
     */
    private fun listApps(): List<Map<String, Any?>> {
        val pm = packageManager
        val out = mutableListOf<Map<String, Any?>>()
        val apps = pm.getInstalledApplications(PackageManager.GET_META_DATA)
        for (info in apps) {
            if (info.packageName == packageName) continue
            val isSystem = (info.flags and ApplicationInfo.FLAG_SYSTEM) != 0
            if (isSystem && pm.getLaunchIntentForPackage(info.packageName) == null) continue
            val label = runCatching {
                pm.getApplicationLabel(info).toString()
            }.getOrNull() ?: info.packageName
            out.add(
                mapOf(
                    "package" to info.packageName,
                    "label" to label,
                    "system" to isSystem,
                ),
            )
        }
        out.sortBy { (it["label"] as? String)?.lowercase() ?: "" }
        return out
    }

    /**
     * 批量取应用图标（32×32 PNG 字节，Dart 侧缩到 32 显示）。
     *
     * 解码要读 drawable，几百个应用同步做会卡主线程，所以放后台线程；
     * 调用方按批（默认 24 个）请求，图标随列表滚动渐进出现。
     */
    private fun listAppIcons(arguments: Any?, result: MethodChannel.Result) {
        val packages = (arguments as? List<*>)?.mapNotNull { it as? String } ?: emptyList()
        Thread {
            val pm = packageManager
            val out = HashMap<String, ByteArray>()
            for (pkg in packages) {
                runCatching {
                    val icon = pm.getApplicationIcon(pkg)
                    val bitmap = drawableToBitmap(icon)
                    val stream = ByteArrayOutputStream()
                    bitmap.compress(Bitmap.CompressFormat.PNG, 100, stream)
                    out[pkg] = stream.toByteArray()
                }
            }
            runOnUiThread { result.success(out) }
        }.apply { isDaemon = true }.start()
    }

    private fun drawableToBitmap(drawable: Drawable): Bitmap {
        if (drawable is BitmapDrawable && drawable.bitmap != null) {
            val source = drawable.bitmap
            if (source.width == ICON_SIZE && source.height == ICON_SIZE) return source
            return Bitmap.createScaledBitmap(source, ICON_SIZE, ICON_SIZE, true)
        }
        val bitmap = Bitmap.createBitmap(ICON_SIZE, ICON_SIZE, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        drawable.setBounds(0, 0, canvas.width, canvas.height)
        drawable.draw(canvas)
        return bitmap
    }

    private fun requestStart(arguments: Map<*, *>, result: MethodChannel.Result) {
        // 仅代理端口模式不接管流量，不需要 VPN 授权。
        val proxyMode = arguments["proxyMode"] as? String ?: "tun"
        if (proxyMode == "port") {
            startServiceWith(arguments)
            result.success(mapOf("pending" to false))
            return
        }
        val consent = VpnService.prepare(this)
        if (consent != null) {
            pendingStart = arguments
            startActivityForResult(consent, REQUEST_VPN_PERMISSION)
            result.success(mapOf("pending" to true))
        } else {
            startServiceWith(arguments)
            result.success(mapOf("pending" to false))
        }
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode == REQUEST_VPN_PERMISSION) {
            val arguments = pendingStart
            pendingStart = null
            if (resultCode == Activity.RESULT_OK && arguments != null) {
                startServiceWith(arguments)
                RuntimeBridge.notifyState("starting")
            } else {
                MihomoCore.log("用户拒绝了 VPN 授权")
                RuntimeBridge.notifyState("error", message = "用户拒绝了 VPN 授权")
            }
            return
        }
        @Suppress("DEPRECATION")
        super.onActivityResult(requestCode, resultCode, data)
    }

    private fun startServiceWith(arguments: Map<*, *>) {
        val workDir = arguments["workDir"] as? String ?: filesDir.absolutePath
        val port = (arguments["port"] as? Number)?.toInt() ?: 9090
        val secret = arguments["secret"] as? String
        val proxyMode = arguments["proxyMode"] as? String ?: "tun"
        val routeMode = arguments["routeMode"] as? String ?: "all"
        val routeApps = (arguments["routeApps"] as? List<*>)?.mapNotNull { it as? String }
            ?: emptyList()
        val mtu = (arguments["mtu"] as? Number)?.toInt() ?: 9000
        val tunAddress = arguments["tunAddress"] as? String

        val intent = Intent(this, ClashVpnService::class.java)
            .setAction(ClashVpnService.ACTION_START)
            .putExtra(ClashVpnService.EXTRA_WORK_DIR, workDir)
            .putExtra(ClashVpnService.EXTRA_PORT, port)
            .putExtra(ClashVpnService.EXTRA_SECRET, secret)
            .putExtra(ClashVpnService.EXTRA_PROXY_MODE, proxyMode)
            .putExtra(ClashVpnService.EXTRA_ROUTE_MODE, routeMode)
            .putExtra(ClashVpnService.EXTRA_MTU, mtu)
            .putExtra(ClashVpnService.EXTRA_TUN_ADDRESS, tunAddress)
            .putStringArrayListExtra(ClashVpnService.EXTRA_ROUTE_APPS, ArrayList(routeApps))

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(intent)
        } else {
            startService(intent)
        }
    }

    private fun sendServiceAction(action: String) {
        val intent = Intent(this, ClashVpnService::class.java).setAction(action)
        if (action == ClashVpnService.ACTION_START && Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(intent)
        } else {
            startService(intent)
        }
    }
}
