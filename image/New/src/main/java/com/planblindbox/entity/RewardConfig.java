package com.planblindbox.entity;

import lombok.Data;

/** 由 reward_config 表管理奖励，不在 Java 代码中硬编码数值。 */
@Data
public class RewardConfig {
    private Long rewardConfigId;
    private String type;
    private Integer coin;
    private Long exp;
    private Integer water;
    private Boolean enabled;
}
