package com.planblindbox.mapper;

import com.planblindbox.entity.Task;
import org.apache.ibatis.annotations.*;

import java.util.List;

public interface TaskMapper {

    @Insert("""
            INSERT INTO task (
                user_id,
                title,
                note,
                start_time,
                end_time,
                target_count,
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
                #{title},
                #{note},
                #{startTime},
                #{endTime},
                #{targetCount},
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


    @Update("""
            UPDATE task
            SET
                title = #{title},
                note = #{note},
                start_time = #{startTime},
                end_time = #{endTime},
                target_count = #{targetCount},
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