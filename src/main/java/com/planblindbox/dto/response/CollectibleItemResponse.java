package com.planblindbox.dto.response;

import lombok.Data;

@Data
public class CollectibleItemResponse {
    private Long itemId;
    private Long packId;
    private String itemKey;
    private String name;
    private String rarity;
    private String description;
    private String imagePath;
    private Integer sortOrder;
    private Integer ownedCount;
    private Boolean owned;
}
