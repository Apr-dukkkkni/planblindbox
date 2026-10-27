package com.planblindbox.dto.request;

import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;
import lombok.Data;

@Data
public class TaskCategoryUpdateRequest {
    @Size(max = 50)
    private String name;

    @Pattern(regexp = "^#[0-9A-Fa-f]{6}$", message = "颜色必须是 #RRGGBB 格式")
    private String color;

    /** false 表示停用；分类停用而非物理删除，以保留历史引用。 */
    private Boolean enabled;
}
