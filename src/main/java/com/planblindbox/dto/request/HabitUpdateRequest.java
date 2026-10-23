package com.planblindbox.dto.request;

import com.fasterxml.jackson.databind.JsonNode;
import com.planblindbox.enums.HabitStatus;
import jakarta.validation.constraints.Size;
import lombok.Data;

import java.time.LocalDate;

@Data
public class HabitUpdateRequest {
    /** null 表示不更新；当前阶段暂不支持将已有 note/endDate 清空为 null。 */
    @Size(min = 1, max = 100)
    private String name;
    private String note;
    private LocalDate startDate;
    private LocalDate endDate;
    private JsonNode repeatRule;
    /** 仅允许 ACTIVE / PAUSED；归档走 DELETE。 */
    private HabitStatus status;
}
