package com.planblindbox.dto.response;

import com.planblindbox.enums.TaskStatus;
import lombok.Data;

import java.math.BigDecimal;
import java.time.LocalDateTime;

@Data
public class TaskResponse {

    private Long taskId;

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
}