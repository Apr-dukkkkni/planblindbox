package com.planblindbox.dto.response;

import java.time.LocalDate;
import java.util.List;

/** 日历某月的每日汇总，日期采用凌晨 5 点换日后的业务日期。 */
public record CalendarMonthResponse(String month, List<DaySummary> days) {
    public record DaySummary(LocalDate date, long completedTasks, long habitCheckIns,
                             long timeRecordCount, long timeMinutes) {}
}
