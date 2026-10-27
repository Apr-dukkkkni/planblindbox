package com.planblindbox.dto.response;

import java.time.LocalDate;
import java.util.List;

/** 所有日期均为凌晨 5 点换日后的业务日期。 */
public record StatsResponse(int days, LocalDate startDate, LocalDate endDate,
                            Summary summary, List<DailyPoint> daily) {

    public record Summary(
            long completedTasks,
            long habitCheckIns,
            long coinEarned,
            long coinSpent,
            long expEarned,
            long coinBalance,
            long expBalance,
            long waterBalance
    ) {}

    public record DailyPoint(
            LocalDate date,
            long completedTasks,
            long habitCheckIns,
            long coinEarned,
            long coinSpent,
            long expEarned,
            long coinBalance,
            long expBalance
    ) {}
}
