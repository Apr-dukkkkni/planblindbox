package com.planblindbox.dto.response;

import java.time.LocalDate;
import java.util.List;

public record CalendarMonthResponse(
        String month,
        List<DaySummary> days
) {
    public record DaySummary(
            LocalDate date,
            long completedTasks,
            long habitCheckIns,
            long totalTasks,
            long totalHabits,
            double completionRate,
            long timeRecordCount,
            long timeMinutes
    ) {}
}