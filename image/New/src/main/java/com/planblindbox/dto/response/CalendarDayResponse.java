package com.planblindbox.dto.response;

import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.List;

/** 指定业务日期的任务、习惯和时间块。未完成项由当前计划时间范围推算。 */
public record CalendarDayResponse(
        LocalDate date,
        List<TaskItem> tasks,
        List<HabitItem> habits,
        List<TimeRecordResponse> timeRecords
) {
    public record TaskItem(
            Long taskId,
            String title,
            String status,
            boolean overdue,
            int actualCount,
            int targetCount,
            LocalDateTime finishTime
    ) {}

    public record HabitItem(Long habitId, String name, boolean checkedIn, int actualCount) {}
}
