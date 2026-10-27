package com.planblindbox.entity;

import com.planblindbox.enums.HabitRecordStatus;
import lombok.Data;

import java.time.LocalDate;
import java.time.LocalDateTime;

@Data
public class HabitRecord {
    private Long habitRecordId;
    private Long habitId;
    private LocalDate recordDate;
    private HabitRecordStatus status;
    private LocalDateTime finishTime;
    private Integer actualCount;
    private LocalDateTime createTime;
    private LocalDateTime updateTime;
}
