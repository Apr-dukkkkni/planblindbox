package com.planblindbox.entity;

import com.planblindbox.enums.TaskRecordStatus;
import lombok.Data;

import java.time.LocalDate;
import java.time.LocalDateTime;

/**
 * 每个任务每天一条汇总记录（task_id + record_date 唯一）。
 * actualCount 为当日累计完成数量，不是历史总完成数量。
 */
@Data
public class TaskRecord {

    private Long taskRecordId;

    private Long taskId;

    private LocalDate recordDate;

    private TaskRecordStatus status;

    private LocalDateTime finishTime;

    private Integer actualCount;

    private LocalDateTime createTime;

    private LocalDateTime updateTime;
}
