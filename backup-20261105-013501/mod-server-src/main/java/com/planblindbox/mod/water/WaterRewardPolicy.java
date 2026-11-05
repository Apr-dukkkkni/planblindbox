package com.planblindbox.mod.water;

/** 阶梯奖励参数为当前试运行方案，产品上线前可单独确认调整。 */
public final class WaterRewardPolicy {
    private WaterRewardPolicy() {}

    /** 固定后端业务时区：凌晨 05:00 前仍是上一签到业务日。 */
    public static java.time.LocalDate businessDate(java.time.Clock clock) {
        var now = java.time.ZonedDateTime.now(clock);
        return now.toLocalTime().isBefore(java.time.LocalTime.of(5,0))
            ? now.toLocalDate().minusDays(1) : now.toLocalDate();
    }

    public static int reward(int streak) {
        if (streak < 1) throw new IllegalArgumentException("streak must be >= 1");
        // 每连续 10 日提升 5 滴，最长计至第 90 日；日 90 之后不再增长。
        int effective = Math.min(streak, 90);
        return 5 + ((effective - 1) / 10) * 5;
    }
}
