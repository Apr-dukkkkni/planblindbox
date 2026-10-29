package com.planblindbox.entity;

import lombok.Data;

import java.time.LocalDate;
import java.time.LocalDateTime;

@Data
public class DailySignIn {

    private Long signInId;
    private Long userId;
    private LocalDate businessDate;
    private Integer streakDay;
    private Integer baseWater;
    private Integer bonusWater;
    private Integer totalWater;
    private LocalDateTime createTime;
}