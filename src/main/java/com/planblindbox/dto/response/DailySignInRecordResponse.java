package com.planblindbox.dto.response;

import lombok.Data;

import java.time.LocalDate;

@Data
public class DailySignInRecordResponse {

    private LocalDate businessDate;

    private Integer streakDay;

    private Integer baseWater;

    private Integer bonusWater;

    private Integer totalWater;
}