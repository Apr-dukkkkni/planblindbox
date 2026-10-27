package com.planblindbox.dto.request;

import com.fasterxml.jackson.databind.JsonNode;
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

    /** 可选截止时间；未传入时默认使用下一个业务日切换点（凌晨 05:00）。 */
    private LocalDateTime endTime;

    @Min(1)
    private Integer targetCount = 1;

    /** 任务分类 ID；0 或 null 表示未分类。 */
    @Min(0)
    private Long categoryId;

    private JsonNode recordRule;

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