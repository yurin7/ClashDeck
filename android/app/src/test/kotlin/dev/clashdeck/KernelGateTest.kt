package dev.clashdeck

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class KernelGateTest {
    @Test
    fun runningWithLiveServiceIsActive() {
        assertTrue(KernelGate.isActive("running", serviceAlive = true, pid = -1, pidAlive = false))
    }

    @Test
    fun runningWithLivePidIsActive() {
        assertTrue(KernelGate.isActive("running", serviceAlive = false, pid = 123, pidAlive = true))
    }

    @Test
    fun staleRunningWithoutProcessIsNotActive() {
        assertFalse(KernelGate.isActive("running", serviceAlive = false, pid = 8090, pidAlive = false))
    }

    @Test
    fun startingStateIsTreatedAsActiveOnlyWhenAlive() {
        assertTrue(KernelGate.isActive("starting", serviceAlive = true, pid = -1, pidAlive = false))
        assertFalse(KernelGate.isActive("starting", serviceAlive = false, pid = -1, pidAlive = false))
    }

    @Test
    fun stoppedAndErrorAreNeverActive() {
        assertFalse(KernelGate.isActive("stopped", serviceAlive = true, pid = 1, pidAlive = true))
        assertFalse(KernelGate.isActive("error", serviceAlive = true, pid = 1, pidAlive = true))
    }

    @Test
    fun staleStartIsNotSwallowed() {
        // force-stop 后 prefs 残留 running，但服务与进程都不在：ACTION_START 必须继续。
        assertFalse(KernelGate.shouldSwallowStart("running", false, 8090, false))
        assertTrue(KernelGate.shouldSwallowStart("running", true, 8090, false))
    }
}