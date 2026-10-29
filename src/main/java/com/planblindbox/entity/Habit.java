package com.planblindbox.entity;

import com.planblindbox.enums.HabitStatus;
import lombok.Data;

import java.time.LocalDate;
import java.time.LocalDateTime;

@Data
public class Habit {
    private Long habitId;
    private Long userId;
    private String name;
    private String note;
    private LocalDate startDate;
    private LocalDate endDate;
    private Integer importance;
    private Integer difficulty;

    /** 数据库 JSON 原文。不要将数据库 JSON 字段直接暴露到前端。 */
    private String repeatRule;
    private HabitStatus status;
    private LocalDateTime createTime;
    private LocalDateTime updateTime;
}
