package com.planblindbox.dto.request;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Pattern;

/** 每一次用户主动点击开盒，生成一个新的 UUID；网络重试必须复用同一个 UUID。 */
public record ShopOpenRequest(
    @NotBlank(message = "requestId 不能为空")
    @Pattern(regexp = "^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$",
             message = "requestId 必须是 UUID")
    String requestId
) {}
