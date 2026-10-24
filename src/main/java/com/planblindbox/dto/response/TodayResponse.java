package com.planblindbox.dto.response;

import com.fasterxml.jackson.annotation.JsonFormat;
import com.planblindbox.enums.TaskStatus;
import lombok.Data;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.List;

/** 今日首页聚合响应。只包含展示所需的数据，不携带奖励结算信息。 */
@Data
public class TodayResponse {
    @JsonFormat(shape = JsonFormat.Shape.STRING, pattern = "yyyy-MM-dd")
    private LocalDate date;
    private List<TaskItem> tasks;
    private List<HabitItem> habits;
    private Asset assets;
    private Summary summary;

    @Data
    public static class TaskItem {
        private Long taskId;
        private String title;
        private String note;
        private LocalDateTime startTime;
        private LocalDateTime endTime;
        private BigDecimal priorityScore;
        /** 重要程度 1-5，用于首页排序，不影响奖励。 */
        private Integer importance;
        /** 难度 1-5，仅回传展示；本步骤不参与奖励结算。 */
        private Integer difficulty;
        private TaskStatus status;
        private Integer targetCount;
        private int todayActualCount;
        private long totalActualCount;
        private long remainingCount;
        private boolean completedToday;
        private boolean overdue;
    }

    @Data
    public static class HabitItem {
        private Long habitId;
        private String name;
        private String note;
        private boolean checkedInToday;
        private int currentStreak;
        private int totalCheckInDays;
    }

    @Data
    public static class Asset {
        private int coin;
        private long exp;
        private int water;
    }

    @Data
    public static class Summary {
        private int taskTotal;
        private int taskCompleted;
        private int habitTotal;
        private int habitCheckedIn;
        /** 完成百分比，例如 71.43 代表 71.43%。 */
        private BigDecimal completionRate;
    }
}
