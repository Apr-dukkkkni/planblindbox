package com.planblindbox.mapper;

import com.planblindbox.entity.Task;
import org.apache.ibatis.annotations.*;

import java.util.List;

public interface TaskMapper {

    @Insert("""
            INSERT INTO task (
                user_id,
                category_id,
                title,
                note,
                start_time,
                end_time,
                target_count,
                recurrence_type,
                repeat_interval_days,
                repeat_days,
                cycle_days,
                recurrence_end_date,
                record_rule,
                status,
                importance,
                urgency,
                difficulty,
                priority_score,
                estimated_minutes
            )
            VALUES (
                #{userId},
                #{categoryId},
                #{title},
                #{note},
                #{startTime},
                #{endTime},
                #{targetCount},
                #{recurrenceType},
                #{repeatIntervalDays},
                #{repeatDays},
                #{cycleDays},
                #{recurrenceEndDate},
                #{recordRule},
                #{status},
                #{importance},
                #{urgency},
                #{difficulty},
                #{priorityScore},
                #{estimatedMinutes}
            )
            """)
    @Options(
            useGeneratedKeys = true,
            keyProperty = "taskId",
            keyColumn = "task_id"
    )
    int insert(Task task);


    @Select("""
            SELECT *
            FROM task
            WHERE task_id = #{taskId}
              AND user_id = #{userId}
            """)
    Task selectById(
            @Param("taskId") Long taskId,
            @Param("userId") Long userId
    );


    /** 对 Task 行加排他锁：并发完成同一个 Task 时串行执行。 */
    @Select("""
            SELECT * FROM task
            WHERE task_id = #{taskId} AND user_id = #{userId}
            FOR UPDATE
            """)
    Task selectByIdForUpdate(
            @Param("taskId") Long taskId,
            @Param("userId") Long userId
    );

    /** 完成状态只允许从 PENDING/IN_PROGRESS 变更。 */
    @Update("""
            UPDATE task SET status = #{status}
            WHERE task_id = #{taskId} AND user_id = #{userId}
              AND status IN ('PENDING', 'IN_PROGRESS')
            """)
    int updateProgressStatus(
            @Param("taskId") Long taskId,
            @Param("userId") Long userId,
            @Param("status") com.planblindbox.enums.TaskStatus status
    );


    @Select("""
            SELECT *
            FROM task
            WHERE user_id = #{userId}
              AND status != 'ARCHIVED'
            ORDER BY create_time DESC
            """)
    List<Task> selectByUserId(Long userId);


    /** 日历历史查询使用：包含已归档任务，是否展示由当天记录与时间范围决定。 */
    @Select("""
            SELECT * FROM task
            WHERE user_id = #{userId}
            ORDER BY start_time, task_id
            """)
    List<Task> selectAllByUserIdForCalendar(@Param("userId") Long userId);


    @Update("""
            UPDATE task
            SET
                title = #{title},
                note = #{note},
                start_time = #{startTime},
                end_time = #{endTime},
                target_count = #{targetCount},
                recurrence_type = #{recurrenceType},
                repeat_interval_days = #{repeatIntervalDays},
                repeat_days = #{repeatDays},
                cycle_days = #{cycleDays},
                recurrence_end_date = #{recurrenceEndDate},
                category_id = #{categoryId},
                record_rule = #{recordRule},
                status = #{status},
                importance = #{importance},
                urgency = #{urgency},
                difficulty = #{difficulty},
                priority_score = #{priorityScore},
                estimated_minutes = #{estimatedMinutes}
            WHERE task_id = #{taskId}
              AND user_id = #{userId}
            """)
    int update(Task task);


    @Update("""
            UPDATE task
            SET status = 'ARCHIVED'
            WHERE task_id = #{taskId}
              AND user_id = #{userId}
            """)
    int archive(
            @Param("taskId") Long taskId,
            @Param("userId") Long userId
    );
}