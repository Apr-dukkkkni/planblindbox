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
    private Integer priceCoin;
    private String rewardType;
    private Long rewardAmount;
    private Integer coinBalanceAfter;
    private Long expBalanceAfter;
    private Integer waterBalanceAfter;
    private LocalDateTime createdAt;
}
