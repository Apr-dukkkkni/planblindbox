package com.planblindbox.entity;

import java.time.LocalDateTime;
import lombok.Data;

@Data
public class ShopOpenRecord {
    private Long openId;
    private Long userId;
    private Long boxId;
    private String boxName;
    private String requestId;
    private Long rewardId;
    private Long collectibleItemId;
    private Integer priceCoin;
    private String rewardType;
    private Long rewardAmount;
    private Integer coinBalanceAfter;
    private Long expBalanceAfter;
    private Integer waterBalanceAfter;
    private LocalDateTime createdAt;

    // 查询历史记录时由 collectible_item 联表填充；数值奖励时为空。
    private String itemName;
    private String itemRarity;
    private String itemImagePath;
    private String itemDescription;
}
