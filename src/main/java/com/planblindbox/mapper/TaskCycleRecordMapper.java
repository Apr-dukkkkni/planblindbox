package com.planblindbox.mapper;

import com.planblindbox.entity.TaskCycleRecord;
import org.apache.ibatis.annotations.Insert;
import org.apache.ibatis.annotations.Options;
import org.apache.ibatis.annotations.Param;
import org.apache.ibatis.annotations.Select;
import org.apache.ibatis.annotations.Update;

/**
 * 自定义累计周期记录持久化。
 * 调用方先锁定 task 行，再读写周期记录，保证同一任务的周期进度串行更新。
 */
public interface TaskCycleRecordMapper {

    @Select("""
            SELECT *
            FROM task_cycle_record
            WHERE task_id = #{taskId}
              AND cycle_start_date = #{cycleStartDate}
            FOR UPDATE
            """)
    TaskCycleRecord selectForUpdate(
            @Param("taskId") Long taskId,
            @Param("cycleStartDate") java.time.LocalDate cycleStartDate
    );

    @Select("""
            SELECT *
            FROM task_cycle_record
            WHERE task_id = #{taskId}
              AND cycle_start_date = #{cycleStartDate}
            """)
    TaskCycleRecord select(
            @Param("taskId") Long taskId,
            @Param("cycleStartDate") java.time.LocalDate cycleStartDate
    );

    @Insert("""
            INSERT INTO task_cycle_record (
                task_id,
                cycle_start_date,
                cycle_end_date,
                target_count,
                actual_count,
                status,
                reward_granted,
                completed_at
            ) VALUES (
                #{taskId},
                #{cycleStartDate},
                #{cycleEndDate},
                #{targetCount},
                #{actualCount},
                #{status},
                #{rewardGranted},
                #{completedAt}
            )
            """)
    @Options(useGeneratedKeys = true, keyProperty = "cycleRecordId", keyColumn = "cycle_record_id")
    int insert(TaskCycleRecord record);

    @Update("""
            UPDATE task_cycle_record
            SET cycle_end_date = #{cycleEndDate},
                target_count = #{targetCount},
                actual_count = #{actualCount},
                status = #{status},
                reward_granted = #{rewardGranted},
                completed_at = #{completedAt}
            WHERE cycle_record_id = #{cycleRecordId}
            """)
    int update(TaskCycleRecord record);
}
