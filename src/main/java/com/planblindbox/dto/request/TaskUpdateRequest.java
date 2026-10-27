package com.planblindbox.dto.request;

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

    /** 可选的新截止时间；未传入时保留任务原有截止时间。 */
    private LocalDateTime endTime;

    @Min(1)
    private Integer targetCount;

    /** 更新时：未传表示不修改；0 表示清除分类。 */
    @Min(0)
    private Long categoryId;
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