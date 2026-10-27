package com.planblindbox.dto.response;

import lombok.Data;
import java.time.LocalDateTime;

@Data
public class TaskCategoryResponse {
    private Long categoryId;
    private String name;
    private String color;
    private String icon;
    private Boolean defaultCategory;
    private Boolean enabled;
    private LocalDateTime createTime;
    private LocalDateTime updateTime;
}
