package com.planblindbox.entity;

import com.planblindbox.enums.TaskStatus;
import com.planblindbox.enums.TaskRecurrenceType;
import lombok.Data;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.time.LocalDateTime;

@Data
public class Task {

    private Long taskId;

    private Long userId;

    private String title;

    private String note;

    private LocalDateTime startTime;

    private LocalDateTime endTime;

    private Integer targetCount;

    /**
     * 任务计划类型。历史任务及未显式设置类型的任务默认为 ONCE。
     */
    private TaskRecurrenceType recurrenceType = TaskRecurrenceType.ONCE;

    /**
     * REPEAT 模式：每隔多少个业务日执行一次。
     * 与 repeatDays 二选一；repeatDays 有值时按指定星期执行。
     */
    private Integer repeatIntervalDays;

    /**
     * REPEAT 模式的指定星期，逗号分隔的 ISO 星期数字：1=周一 ... 7=周日。
     * 例如 "1,3,5" 表示周一、周三、周五。
     */
    private String repeatDays;

    /**
     * ACCUMULATE 模式：自定义周期长度（业务日）。
     */
    private Integer cycleDays;

    /**
     * 重复/累计计划的可选结束业务日期。与一次性任务的 endTime 截止时刻分开。
     */
    private LocalDate recurrenceEndDate;

    private Long categoryId;

    /**
     * 任务记录规则，保存数据库中的 JSON 原文。
     * NULL 表示 DEFAULT 模式，每次记录 1。
     */
    private String recordRule;

    private TaskStatus status;

    private Integer importance;

    private Integer urgency;

    private Integer difficulty;

    private BigDecimal priorityScore;

    private Integer estimatedMinutes;

    private LocalDateTime createTime;

    private LocalDateTime updateTime;
}