package com.planblindbox.dto.request;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;
import lombok.Data;

@Data
public class TaskCategoryCreateRequest {
    @NotNull
    private Long userId;

    @NotBlank
    @Size(max = 50)
    private String name;

    @Pattern(regexp = "^#[0-9A-Fa-f]{6}$", message = "颜色必须是 #RRGGBB 格式")
    private String color;

    @Size(max = 30)
    private String icon;
}
