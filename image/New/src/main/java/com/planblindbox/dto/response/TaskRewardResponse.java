package com.planblindbox.dto.response;

import lombok.Data;

/** 只表示本次完成任务发放的奖励，不等于历史总奖励。 */
@Data
public class TaskRewardResponse {
    private Boolean granted;
    private Integer coin;
    private Long exp;
    private Integer water;
    private Integer coinBalance;
    private Long expBalance;
    private Integer waterBalance;
}
