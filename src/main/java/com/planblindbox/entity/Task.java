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

    private TaskStatus status;

    private Integer importance;

    private Integer urgency;

    private Integer difficulty;

    private BigDecimal priorityScore;

    private Integer estimatedMinutes;

    private LocalDateTime createTime;

    private LocalDateTime updateTime;
}