package com.planblindbox.entity;

import lombok.Data;

@Data
public class ShopReward {
    private Long rewardId;
    private Long boxId;
    private String assetType;
    private Long amount;
    private Integer weight;
}
