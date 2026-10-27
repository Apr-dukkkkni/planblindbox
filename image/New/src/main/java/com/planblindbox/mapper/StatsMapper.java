package com.planblindbox.mapper;

import lombok.Data;
import org.apache.ibatis.annotations.Param;
import org.apache.ibatis.annotations.Select;

import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.List;

/** 直接从执行记录、打卡记录与资产流水聚合；不维护第二份统计数据。 */
public interface StatsMapper {

    @Data
    class DailyCount {
        private LocalDate day;
        private Long completedCount;
    }

    @Data
    class DailyAssets {
        private LocalDate day;
        private Long coinEarned;
        private Long coinSpent;
        private Long coinNet;
        private Long expEarned;
        private Long expNet;
    }

    // COMPLETED 表示该任务在这一天首次达到目标，按任务数量而非 actual_count 计数。
    @Select("""
            SELECT tr.record_date AS day, COUNT(*) AS completed_count
            FROM task_record tr
            JOIN task t ON t.task_id = tr.task_id
            WHERE t.user_id = #{userId}
              AND tr.record_date BETWEEN #{startDate} AND #{endDate}
              AND tr.status = 'COMPLETED'
            GROUP BY tr.record_date
            ORDER BY tr.record_date
            """)
    List<DailyCount> completedTasks(@Param("userId") Long userId,
                                    @Param("startDate") LocalDate startDate,
                                    @Param("endDate") LocalDate endDate);

    // 每个习惯每天至多一条 habit_record，COMPLETED 表示打卡成功。
    @Select("""
            SELECT hr.record_date AS day, COUNT(*) AS completed_count
            FROM habit_record hr
            JOIN habit h ON h.habit_id = hr.habit_id
            WHERE h.user_id = #{userId}
              AND hr.record_date BETWEEN #{startDate} AND #{endDate}
              AND hr.status = 'COMPLETED'
            GROUP BY hr.record_date
            ORDER BY hr.record_date
            """)
    List<DailyCount> completedHabits(@Param("userId") Long userId,
                                     @Param("startDate") LocalDate startDate,
                                     @Param("endDate") LocalDate endDate);

    // 资产流水 create_time 是自然时刻；减去 5 小时映射到相应业务日期。
    // WHERE 使用 create_time 范围，保留 (user_id, create_time) 索引可用性。
    @Select("""
            SELECT DATE(DATE_SUB(ar.create_time, INTERVAL 5 HOUR)) AS day,
                   COALESCE(SUM(CASE WHEN ar.asset_type = 'COIN' AND ar.amount > 0
                                     THEN ar.amount ELSE 0 END), 0) AS coin_earned,
                   COALESCE(SUM(CASE WHEN ar.asset_type = 'COIN' AND ar.amount < 0
                                     THEN -ar.amount ELSE 0 END), 0) AS coin_spent,
                   COALESCE(SUM(CASE WHEN ar.asset_type = 'COIN'
                                     THEN ar.amount ELSE 0 END), 0) AS coin_net,
                   COALESCE(SUM(CASE WHEN ar.asset_type = 'EXP' AND ar.amount > 0
                                     THEN ar.amount ELSE 0 END), 0) AS exp_earned,
                   COALESCE(SUM(CASE WHEN ar.asset_type = 'EXP'
                                     THEN ar.amount ELSE 0 END), 0) AS exp_net
            FROM asset_record ar
            WHERE ar.user_id = #{userId}
              AND ar.create_time >= #{startAt}
              AND ar.create_time < #{endExclusive}
            GROUP BY DATE(DATE_SUB(ar.create_time, INTERVAL 5 HOUR))
            ORDER BY day
            """)
    List<DailyAssets> dailyAssets(@Param("userId") Long userId,
                                  @Param("startAt") LocalDateTime startAt,
                                  @Param("endExclusive") LocalDateTime endExclusive);
}
