package dev.clashdeck

import org.junit.Assert.assertEquals
import org.junit.Test

class WidgetCopyTest {
    @Test
    fun noSnapshotAsksUserToStartInApp() {
        assertEquals("请先在 App 内启动一次内核", WidgetCopy.subtitle(false, "demo.yaml", "DEFAULT"))
    }

    @Test
    fun snapshotShowsProfileAndExit() {
        assertEquals("demo.yaml · DEFAULT", WidgetCopy.subtitle(true, "demo.yaml", "DEFAULT"))
    }

    @Test
    fun snapshotWithoutFieldsFallsBackToHint() {
        assertEquals("轻点打开 ClashDeck", WidgetCopy.subtitle(true, "  ", null))
    }

    @Test
    fun titleReflectsKernelState() {
        assertEquals("已连接", WidgetCopy.title(true, RuntimePrefs.STATE_RUNNING))
        assertEquals("启动中", WidgetCopy.title(false, RuntimePrefs.STATE_STARTING))
        assertEquals("启动失败", WidgetCopy.title(false, RuntimePrefs.STATE_ERROR))
        assertEquals("已停止", WidgetCopy.title(false, RuntimePrefs.STATE_STOPPED))
    }
}