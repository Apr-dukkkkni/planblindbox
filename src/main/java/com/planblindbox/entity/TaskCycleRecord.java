package com.planblindbox.entity;

import lombok.Data;

import java.time.LocalDate;
import java.time.LocalDateTime;

/**
 * 自定义累计周期的持久化记录。
 * task_id + cycle_start_date 唯一，确保同一任务同一周期只有一条进度/奖励记录。
 */
@Data
public class TaskCycleRecord {

    private Long cycleRecordId;

    private Long taskId;

    private LocalDate cycleStartDate;

    private LocalDate cycleEndDate;

    private Integer targetCount;

    private Integer actualCount;

    /** IN_PROGRESS / COMPLETED */
    private String status;

    /** 此周期的奖励是否已结算，防止重复发奖。 */
    private Boolean rewardGranted;

    private LocalDateTime completedAt;

    private LocalDateTime createTime;

    private LocalDateTime updateTime;
}
