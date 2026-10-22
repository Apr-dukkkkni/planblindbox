package com.planblindbox.dto.request;

import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Positive;
import lombok.Data;

import java.time.LocalDateTime;

@Data
public class TaskCreateRequest {

    @NotNull
    private Long userId;

    @NotBlank
    private String title;

    private String note;

    private LocalDateTime startTime;

    private LocalDateTime endTime;

    @Min(1)
    private Integer targetCount = 1;

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