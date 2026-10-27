package com.planblindbox.entity;

import lombok.Data;

import java.time.LocalDate;
import java.time.LocalDateTime;

@Data
public class TimeRecord {
    private Long timeRecordId;
    private Long userId;
    private Long taskId;
    private String title;
    private String category;
    private LocalDateTime startTime;
    private LocalDateTime endTime;
    private Integer durationMinutes;
    private LocalDate recordDate;
    private String note;
    private LocalDateTime createTime;
    private LocalDateTime updateTime;
}
