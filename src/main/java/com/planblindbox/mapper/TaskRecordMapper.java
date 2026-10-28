package com.planblindbox.mapper;

import com.planblindbox.entity.TaskRecord;
import com.planblindbox.enums.TaskRecordStatus;
import org.apache.ibatis.annotations.Insert;
import org.apache.ibatis.annotations.Options;
import org.apache.ibatis.annotations.Param;
import org.apache.ibatis.annotations.Select;
import org.apache.ibatis.annotations.Update;

import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.List;

/**
 * 这里只处理执行记录的持久化，不直接对外提供 API。
 * 后续 /tasks/{taskId}/complete 将统一负责校验、并发控制、任务状态和奖励。
 */
public interface TaskRecordMapper {

    @Insert("""
            INSERT INTO task_record (
                task_id,
                record_date,
                status,
                finish_time,
                actual_count
            ) VALUES (
                #{taskId},
                #{recordDate},
                #{status},
                #{finishTime},
                #{actualCount}
            )
            """)
    @Options(
            useGeneratedKeys = true,
            keyProperty = "taskRecordId",
            keyColumn = "task_record_id"
    )
    int insert(TaskRecord record);

    @Select("""
            SELECT *
            FROM task_record
            WHERE task_id = #{taskId}
              AND record_date = #{recordDate}
            """)
    TaskRecord selectByTaskIdAndDate(
            @Param("taskId") Long taskId,
            @Param("recordDate") LocalDate recordDate
    );

    @Select("""
            SELECT *
            FROM task_record
            WHERE task_id = #{taskId}
            ORDER BY record_date DESC
            """)
    List<TaskRecord> selectByTaskId(@Param("taskId") Long taskId);

    @Select("""
            SELECT tr.*
            FROM task_record tr
            JOIN task t ON t.task_id = tr.task_id
            WHERE t.user_id = #{userId}
              AND tr.record_date = #{recordDate}
            """)
    List<TaskRecord> selectByUserIdAndDate(@Param("userId") Long userId,
                                           @Param("recordDate") LocalDate recordDate);


    @Select("""
            SELECT COALESCE(SUM(actual_count), 0)
            FROM task_record
            WHERE task_id = #{taskId}
            """)
    Long sumActualCount(@Param("taskId") Long taskId);

    /** 查询指定业务日期范围内的累计执行数量（两端均包含）。 */
    @Select("""
            SELECT COALESCE(SUM(actual_count), 0)
            FROM task_record
            WHERE task_id = #{taskId}
              AND record_date BETWEEN #{startDate} AND #{endDate}
            """)
    Long sumActualCountBetween(
            @Param("taskId") Long taskId,
            @Param("startDate") LocalDate startDate,
            @Param("endDate") LocalDate endDate
    );

    /**
     * 原子累加当日数量，避免先读后写造成丢失更新。
     * 同日首次创建由调用方负责；后续在 Task Service 中锁定任务行再处理。
     */
    @Update("""
            UPDATE task_record
            SET actual_count = actual_count + #{increment}
            WHERE task_record_id = #{taskRecordId}
            """)
    int incrementActualCount(
            @Param("taskRecordId") Long taskRecordId,
            @Param("increment") int increment
    );

    @Update("""
            UPDATE task_record
            SET status = #{status},
                finish_time = #{finishTime}
            WHERE task_record_id = #{taskRecordId}
            """)
    int updateStatus(
            @Param("taskRecordId") Long taskRecordId,
            @Param("status") TaskRecordStatus status,
            @Param("finishTime") LocalDateTime finishTime
    );
}
