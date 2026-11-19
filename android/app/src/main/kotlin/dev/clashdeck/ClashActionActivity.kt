package dev.clashdeck

import android.app.Activity
import android.content.Intent
import android.net.VpnService
import android.os.Build
import android.os.Bundle
import android.widget.Toast

/**
 * 无界面的启停入口。
 *
 * 桌面小组件、快捷设置磁贴和常驻通知都通过 [Intent] 指向这里，避免为了开关内核
 * 把整个 App 界面拉起来。只有从未在 App 内启动过（缺少参数快照）时，才会回退到
 * [MainActivity] 并提示先手动启动一次。
 */
class ClashActionActivity : Activity() {
    companion object {
        const val ACTION_START = "dev.clashdeck.action.ACTION_START"
        const val ACTION_STOP = "dev.clashdeck.action.ACTION_STOP"
        private const val REQUEST_VPN_PERMISSION = 0x2001
    }

    private var pendingStart: Map<String, Any?>? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        when (intent?.action) {
            ACTION_START -> requestStart()
            ACTION_STOP -> requestStop()
            else -> finish()
        }
    }

    private fun requestStart() {
        val arguments = RuntimePrefs.loadStart(this)
        if (arguments == null) {
            // 还没有任何启动参数：只能先让用户在 App 里启动一次，内核配置来自 Dart。
            Toast.makeText(this, "请先在 App 内启动一次内核", Toast.LENGTH_LONG).show()
            startActivity(
                Intent(this, MainActivity::class.java)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP),
            )
            finish()
            return
        }
        val state = RuntimePrefs.kernelState(this)
        // prefs 可能因 force-stop / 系统回收而残留 running：只有进程真的活着才 no-op。
        if (RuntimePrefs.isKernelAlive(this) &&
            (state == RuntimePrefs.STATE_RUNNING || state == RuntimePrefs.STATE_STARTING)
        ) {
            finish()
            return
        }
        if (state != RuntimePrefs.STATE_STOPPED) {
            RuntimePrefs.setKernel(this, RuntimePrefs.STATE_STOPPED)
        }
        val proxyMode = arguments["proxyMode"] as? String ?: "tun"
        if (proxyMode == "port") {
            startServiceNow(arguments)
            return
        }
        val consent = VpnService.prepare(this)
        if (consent == null) {
            startServiceNow(arguments)
            return
        }
        pendingStart = arguments
        @Suppress("DEPRECATION")
        startActivityForResult(consent, REQUEST_VPN_PERMISSION)
    }

    private fun requestStop() {
        RuntimePrefs.setKernel(this, RuntimePrefs.STATE_STOPPING)
        val stop = Intent(this, ClashVpnService::class.java)
            .setAction(ClashVpnService.ACTION_STOP)
            .putExtra(ClashVpnService.EXTRA_FROM_ACTION, true)
        startService(stop)
        finish()
    }

    private fun startServiceNow(arguments: Map<String, Any?>) {
        RuntimePrefs.setKernel(this, RuntimePrefs.STATE_STARTING)
        val args = arguments
        val routeApps = (args["routeApps"] as? List<*>)?.mapNotNull { it as? String }
            ?: emptyList()
        val intent = Intent(this, ClashVpnService::class.java)
            .setAction(ClashVpnService.ACTION_START)
            .putExtra(ClashVpnService.EXTRA_WORK_DIR, args["workDir"] as? String)
            .putExtra(ClashVpnService.EXTRA_PORT, (args["port"] as? Number)?.toInt() ?: 9090)
            .putExtra(ClashVpnService.EXTRA_SECRET, args["secret"] as? String)
            .putExtra(ClashVpnService.EXTRA_PROXY_MODE, args["proxyMode"] as? String ?: "tun")
            .putExtra(ClashVpnService.EXTRA_ROUTE_MODE, args["routeMode"] as? String ?: "all")
            .putExtra(ClashVpnService.EXTRA_MTU, (args["mtu"] as? Number)?.toInt() ?: 9000)
            .putExtra(ClashVpnService.EXTRA_TUN_ADDRESS, args["tunAddress"] as? String)
            .putExtra(ClashVpnService.EXTRA_IPV6, args["ipv6"] as? Boolean ?: false)
            .putExtra(ClashVpnService.EXTRA_PROFILE_NAME, args["profileName"] as? String)
            .putExtra(ClashVpnService.EXTRA_GLOBAL_EXIT, args["globalExit"] as? String)
            .putStringArrayListExtra(ClashVpnService.EXTRA_ROUTE_APPS, ArrayList(routeApps))
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(intent)
        } else {
            startService(intent)
        }
        finish()
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode == REQUEST_VPN_PERMISSION) {
            val arguments = pendingStart
            pendingStart = null
            if (resultCode == RESULT_OK && arguments != null) {
                startServiceNow(arguments)
            } else {
                RuntimePrefs.setKernel(this, RuntimePrefs.STATE_STOPPED)
                Toast.makeText(this, "未获得 VPN 授权，内核未启动", Toast.LENGTH_LONG).show()
                finish()
            }
            return
        }
        @Suppress("DEPRECATION")
        super.onActivityResult(requestCode, resultCode, data)
    }
}
