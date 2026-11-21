package dev.clashdeck

import android.net.LocalServerSocket
import android.net.LocalSocket
import android.net.VpnService
import android.os.ParcelFileDescriptor
import android.os.Process
import android.system.Os
import java.io.Closeable
import java.io.IOException
import java.util.UUID
import java.util.concurrent.atomic.AtomicBoolean

/** Applies the VPN owner's socket protection to descriptors from its core subprocess. */
internal class CoreSocketProtector(private val vpn: VpnService) : Closeable {
    val name = "clashdeck-protect-${UUID.randomUUID()}"
    private val server = LocalServerSocket(name)
    private val closed = AtomicBoolean(false)

    init {
        Thread(::serve, "clashdeck-protect").apply {
            isDaemon = true
            start()
        }
    }

    private fun serve() {
        while (!closed.get()) {
            val client = try {
                server.accept()
            } catch (e: IOException) {
                if (!closed.get()) MihomoCore.log("接收内核出站套接字失败：${e.message}")
                return
            }
            runCatching { client.use(::handle) }
        }
    }

    private fun handle(client: LocalSocket) {
        if (client.peerCredentials.uid != Process.myUid()) return
        client.soTimeout = 3000
        val request = client.inputStream.read()
        val descriptors = client.ancillaryFileDescriptors ?: emptyArray()
        try {
            val protected = request == 1 && descriptors.size == 1 && !closed.get() &&
                ParcelFileDescriptor.dup(descriptors[0]).use { vpn.protect(it.fd) }
            client.outputStream.write(if (protected) 1 else 0)
        } finally {
            descriptors.forEach { fd -> runCatching { Os.close(fd) } }
        }
    }

    override fun close() {
        if (closed.compareAndSet(false, true)) runCatching { server.close() }
    }
}
