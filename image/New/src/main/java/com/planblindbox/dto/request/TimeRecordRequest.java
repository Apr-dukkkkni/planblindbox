package com.planblindbox.dto.request;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Positive;
import jakarta.validation.constraints.Size;
import lombok.Data;

import java.time.LocalDateTime;

/** 创建或更新手动时间块；业务日期由后端根据开始时间计算，不接受客户端指定。 */
@Data
public class TimeRecordRequest {
    @NotBlank
    @Size(max = 100)
    private String title;

    @NotBlank
    @Size(max = 50)
    private String category;

    @NotNull
    private LocalDateTime startTime;

    @NotNull
    private LocalDateTime endTime;

    @Positive
    private Long taskId;

    @Size(max = 500)
    private String note;
}
