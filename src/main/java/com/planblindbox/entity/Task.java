package com.planblindbox.entity;

import com.planblindbox.enums.TaskStatus;
import lombok.Data;

import java.math.BigDecimal;
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