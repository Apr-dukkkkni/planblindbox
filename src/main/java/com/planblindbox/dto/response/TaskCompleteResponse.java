package com.planblindbox.dto.response;

import com.planblindbox.enums.TaskStatus;
import lombok.Data;

import java.time.LocalDate;

@Data
public class TaskCompleteResponse {
    private Long taskId;
    private LocalDate recordDate;
    private Integer incrementCount;
    private Integer todayActualCount;
    private Long totalActualCount;
    private Integer targetCount;
    private Integer remainingCount;
    private TaskStatus status;
}
