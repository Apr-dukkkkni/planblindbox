package com.planblindbox.dto.response;

public record ShopOpenResponse(
        Long openId,
        String requestId,
        Long boxId,
        String boxName,
        int priceCoin,
        String rewardType,
        long rewardAmount,
        int coinBalance,
        long expBalance,
        int waterBalance,
        Long itemId,
        String itemName,
        String itemRarity,
        String itemImagePath,
        String itemDescription
) {}
