package com.planblindbox.dto.response;

import lombok.Data;

/** 本次打卡发放的奖励与发放后的总余额。 */
@Data
public class HabitRewardResponse {
    private Boolean granted;
    private Integer coin;
    private Long exp;
    private Integer water;
    private Integer coinBalance;
    private Long expBalance;
    private Integer waterBalance;
}
