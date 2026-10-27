package com.planblindbox.entity;

import lombok.Data;

@Data
public class UserAsset {
    private Long assetId;
    private Long userId;
    private Integer coin;
    private Long exp;
    private Integer water;
}
