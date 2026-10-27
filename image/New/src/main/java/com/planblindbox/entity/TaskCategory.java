package com.planblindbox.entity;

import lombok.Data;
import java.time.LocalDateTime;

@Data
public class TaskCategory {
    private Long categoryId;
    private Long userId;
    private String name;
    private String color;
    private String icon;
    private Boolean defaultCategory;
    private Boolean enabled;
    private LocalDateTime createTime;
    private LocalDateTime updateTime;
}
