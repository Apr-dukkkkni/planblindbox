package com.planblindbox.dto.request;

import com.fasterxml.jackson.databind.JsonNode;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Positive;
import jakarta.validation.constraints.Size;
import lombok.Data;

import java.time.LocalDate;

@Data
public class HabitCreateRequest {
    /** MVP 临时由前端传 userId；登录接入后从认证上下文获取。 */
    @NotNull @Positive
    private Long userId;

    @NotBlank @Size(max = 100)
    private String name;

    private String note;

    @NotNull
    private LocalDate startDate;

    private LocalDate endDate;

    /** 如 {"type":"DAILY"} 或 {"type":"WEEKLY","daysOfWeek":[1,3,5]}。 */
    @NotNull
    private JsonNode repeatRule;
}
