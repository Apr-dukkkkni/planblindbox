package com.planblindbox.dto.request;

import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Positive;
import lombok.Data;

/** 每次调用追加的执行数量，不是累计总量。 */
@Data
public class TaskCompleteRequest {
    @NotNull
    @Positive
    private Integer actualCount;
}
