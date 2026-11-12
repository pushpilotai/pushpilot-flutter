package ai.pushpilot.pushpilot_flutter

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** The plugin's own Android glue that runs without Android: holding taps and links until Dart starts. */
class DartGateTest {
    /** Work from before init waits, then runs in arrival order; later work runs at once. */
    @Test
    fun workWaitsForStartThenRunsInOrder() {
        val gate = DartGate()
        val ran = mutableListOf<String>()
        gate.run { ran += "link" }
        gate.run { ran += "tap" }
        assertTrue(ran.isEmpty())
        gate.start()
        gate.run { ran += "later" }
        assertEquals(listOf("link", "tap", "later"), ran)
    }

    /** After the starting engine goes away, work waits again for the next init, and runs once. */
    @Test
    fun stopHoldsWorkUntilTheNextStart() {
        val gate = DartGate()
        val ran = mutableListOf<String>()
        gate.start()
        gate.stop()
        gate.run { ran += "link" }
        assertTrue(ran.isEmpty())
        gate.start()
        gate.start()
        assertEquals(listOf("link"), ran)
    }

    /** A notification is passed on only the first time it is seen. */
    @Test
    fun eachTapCountsOnce() {
        val gate = DartGate()
        assertTrue(gate.firstTap("n1"))
        assertFalse(gate.firstTap("n1"))
        assertTrue(gate.firstTap("n2"))
    }
}
