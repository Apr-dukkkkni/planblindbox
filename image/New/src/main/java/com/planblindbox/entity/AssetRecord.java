package com.planblindbox.entity;

import lombok.Data;

@Data
public class AssetRecord {
    private Long recordId;
    private Long userId;
    private String action;
    private String assetType;
    private Long amount;
    private String source;
    private Long sourceId;
}
