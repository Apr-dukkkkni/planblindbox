package com.planblindbox.util;

import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.LocalTime;

public final class BusinessTime {

    private static final LocalTime RESET_TIME = LocalTime.of(5, 0);

    private BusinessTime() {}

    // 获取业务日期：凌晨 5 点之前属于前一天。
    public static LocalDate businessDate(LocalDateTime now) {
        LocalDate date = now.toLocalDate();
        return now.toLocalTime().isBefore(RESET_TIME) ? date.minusDays(1) : date;
    }

    // 获取当前时间之后最近一次凌晨 5 点。
    public static LocalDateTime nextReset(LocalDateTime now) {
        return now.toLocalDate().plusDays(1).atTime(RESET_TIME);
    }

    /**
     * 返回任务有效截止时间。
     * 已存在或由用户明确设置的 endTime 必须保留；仅当截止时间缺失时，才按开始/创建时刻
     * 推算默认截止点。这样不会把长期任务的自定义期限改写成次日凌晨 5 点。
     */
    public static LocalDateTime effectiveDeadline(
            LocalDateTime endTime,
            LocalDateTime startTime,
            LocalDateTime createTime
    ) {
        if (endTime != null) {
            return endTime;
        }

        LocalDateTime anchor = createTime;
        if (startTime != null && (anchor == null || startTime.isAfter(anchor))) {
            anchor = startTime;
        }
        return anchor == null ? null : nextReset(anchor);
    }
}
