package com.planblindbox.dto.response;

import java.time.LocalDate;
import java.time.LocalDateTime;

public record TimeRecordResponse(
        Long timeRecordId,
        Long taskId,
        String title,
        String category,
        LocalDateTime startTime,
        LocalDateTime endTime,
        Integer durationMinutes,
        LocalDate recordDate,
        String note
) {}
