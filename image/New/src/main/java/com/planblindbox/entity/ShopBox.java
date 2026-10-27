package com.planblindbox.entity;

import lombok.Data;

@Data
public class ShopBox {
    private Long boxId;
    private String code;
    private String name;
    private String description;
    private Integer priceCoin;
    private Boolean enabled;
}
