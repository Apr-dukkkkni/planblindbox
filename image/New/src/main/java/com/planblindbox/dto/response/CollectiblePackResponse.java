package com.planblindbox.dto.response;

import lombok.Data;

@Data
public class CollectiblePackResponse {
    private Long packId;
    private String packKey;
    private String name;
    private String description;
    private String version;
    private Integer unlockLevel;
    private Long totalItems;
    private Long ownedItems;
}
