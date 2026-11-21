package dev.clashdeck

import java.io.File

/**
 * `runtime.yaml.tpl` 的占位替换。
 *
 * Dart 生成运行配置时会把 `tun` 段里的 `file-descriptor` 写成 0 并另存一份模板；
 * Flutter engine 不在时这里把同一行换成本次真实拿到的 fd，其余字节保持不变。
 */
object RuntimeTemplate {
    private val descriptorLine = Regex("(?m)^(\\s*)file-descriptor:\\s*0\\s*$")
    private val stackLine = Regex("[ \\t]+stack:[ \\t]*(gvisor|system|mixed)[ \\t]*")

    /** Earlier snapshots did not store the stack, but the generated template did. */
    fun tunStack(workDir: File): String? = read(workDir)?.lineSequence()
        ?.dropWhile { it.trimEnd() != "tun:" }
        ?.drop(1)
        ?.takeWhile { it.isBlank() || it.first().isWhitespace() }
        ?.firstNotNullOfOrNull { stackLine.matchEntire(it)?.groupValues?.get(1) }

    /** 读取模板并回填 fd；模板不存在或没有占位行时返回 null。 */
    fun materialize(workDir: File, fd: Int): String? {
        val template = read(workDir) ?: return null
        if (!descriptorLine.containsMatchIn(template)) return null
        return descriptorLine.replace(template) { match -> "${match.groupValues[1]}file-descriptor: $fd" }
    }

    private fun read(workDir: File): String? {
        val templateFile = File(workDir, "runtime.yaml.tpl")
        if (!templateFile.isFile) return null
        return try {
            templateFile.readText()
        } catch (_: Throwable) {
            null
        }
    }
}
