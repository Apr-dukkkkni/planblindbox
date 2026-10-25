package com.planblindbox.dto.request;

import com.fasterxml.jackson.annotation.JsonFormat;
import com.fasterxml.jackson.databind.JsonNode;
import com.planblindbox.enums.TaskStatus;
import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.Positive;
import lombok.Data;

import java.time.LocalDateTime;

@Data
public class TaskUpdateRequest {

    private String title;

    private String note;

    private LocalDateTime startTime;

    private LocalDateTime endTime;

    @Min(1)
    private Integer targetCount;
    private JsonNode recordRule;

    private TaskStatus status;

    @Min(1)
    @Max(5)
    private Integer importance;

    @Min(1)
    @Max(5)
    private Integer urgency;

    @Min(1)
    @Max(5)
    private Integer difficulty;

    @Positive
    private Integer estimatedMinutes;
}