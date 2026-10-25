package com.planblindbox.util;

import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.LocalTime;

public final class BusinessTime {

    private static final LocalTime RESET_TIME =
            LocalTime.of(5, 0);

    private BusinessTime() {}

    // 获取业务日期：凌晨5点之前属于前一天
    public static LocalDate businessDate(LocalDateTime now) {
        LocalDate date = now.toLocalDate();

        return now.toLocalTime().isBefore(RESET_TIME)
                ? date.minusDays(1)
                : date;
    }

    // 获取当前时间之后最近一次凌晨5点
    public static LocalDateTime nextReset(LocalDateTime now) {
        LocalDateTime reset = now.toLocalDate()
                .atTime(RESET_TIME);

        return now.isBefore(reset)
                ? reset
                : reset.plusDays(1);
    }

    // 旧任务可能没有 endTime，按创建时间推算
    public static LocalDateTime effectiveDeadline(
            LocalDateTime endTime,
            LocalDateTime startTime,
            LocalDateTime createTime
    ) {
        if (endTime != null) {
            return endTime;
        }

        LocalDateTime anchor = createTime != null
                ? createTime
                : startTime;

        if (startTime != null &&
                (anchor == null || startTime.isAfter(anchor))) {
            anchor = startTime;
        }

        return anchor == null ? null : nextReset(anchor);
    }
}