package dev.clashdeck

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File

class UpdateFileProvider : FileProvider()

internal class AndroidUpdate(private val activity: Activity) {
    companion object {
        const val CHANNEL = "dev.clashdeck/update"
        private val apkName = Regex("ClashDeck-\\d+\\.\\d+\\.\\d+-(arm64-v8a|x86_64)\\.apk")
    }

    fun handle(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "supportedAbis" -> result.success(Build.SUPPORTED_ABIS.toList())
                "installApk" -> result.success(install(call.arguments as? String))
                "openInstallSettings" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        activity.startActivity(
                            Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES)
                                .setData(Uri.fromParts("package", activity.packageName, null)),
                        )
                    }
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        } catch (error: Exception) {
            result.error("update", error.message ?: "无法打开安装程序", null)
        }
    }

    @Suppress("DEPRECATION")
    private fun install(path: String?): Boolean {
        requireNotNull(path) { "找不到下载的安装包" }
        val directory = File(activity.cacheDir, "updates").canonicalFile
        val apk = File(path).canonicalFile
        require(apk.parentFile == directory && apk.name.matches(apkName) && apk.isFile) {
            "找不到下载的安装包"
        }
        val packageManager = activity.packageManager
        require(packageManager.getPackageArchiveInfo(apk.path, 0)?.packageName == activity.packageName) {
            "安装包与 ClashDeck 不匹配"
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && !packageManager.canRequestPackageInstalls()) {
            return false
        }
        val uri = FileProvider.getUriForFile(activity, "${activity.packageName}.updates", apk)
        activity.startActivity(
            Intent(Intent.ACTION_VIEW)
                .setDataAndType(uri, "application/vnd.android.package-archive")
                .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION),
        )
        return true
    }
}
