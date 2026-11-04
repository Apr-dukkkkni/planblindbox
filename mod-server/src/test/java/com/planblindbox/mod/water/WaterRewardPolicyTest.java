package com.planblindbox.mod.water;
import org.junit.jupiter.api.Test;
import static org.junit.jupiter.api.Assertions.*;
class WaterRewardPolicyTest {
    @Test void fiveAMBoundary() {
        var zone = java.time.ZoneId.of("Asia/Shanghai");
        var before = java.time.Clock.fixed(java.time.Instant.parse("2026-11-03T20:59:00Z"), zone);
        var after = java.time.Clock.fixed(java.time.Instant.parse("2026-11-03T21:00:00Z"), zone);
        assertEquals(java.time.LocalDate.of(2026,11,3), WaterRewardPolicy.businessDate(before));
        assertEquals(java.time.LocalDate.of(2026,11,4), WaterRewardPolicy.businessDate(after));
    }
    @Test void stairStepAndCap() {
        assertEquals(5, WaterRewardPolicy.reward(1));
        assertEquals(5, WaterRewardPolicy.reward(9));
        assertEquals(10, WaterRewardPolicy.reward(11));
        assertEquals(45, WaterRewardPolicy.reward(90));
        assertEquals(45, WaterRewardPolicy.reward(500));
        assertThrows(IllegalArgumentException.class, () -> WaterRewardPolicy.reward(0));
    }
}
