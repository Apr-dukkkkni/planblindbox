package com.planblindbox.dto.response;

import lombok.Data;

import java.time.LocalDate;

@Data
public class DailySignInResponse {

    // 本次请求是否实际发放了奖励
    private boolean granted;

    private LocalDate businessDate;
    private Integer streakDay;
    private Integer baseWater;
    private Integer bonusWater;
    private Integer totalWater;
    private Integer waterBalance;
}