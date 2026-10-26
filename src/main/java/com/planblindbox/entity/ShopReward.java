package com.planblindbox.entity;

import lombok.Data;

@Data
public class ShopReward {
    private Long rewardId;
    private Long boxId;
    private String assetType;
    private Long amount;
    private Integer weight;

    // COLLECTIBLE 奖励关联的收藏品信息，由 ShopMapper 联表查询填充。
    private Long itemId;
    private String itemName;
    private String itemRarity;
    private String itemDescription;
    private String itemImagePath;
    private Boolean itemEnabled;
    private String packStatus;
}
